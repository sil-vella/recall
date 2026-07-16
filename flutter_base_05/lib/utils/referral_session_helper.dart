import 'dart:async';

import 'package:flutter/material.dart';

import '../core/managers/hooks_manager.dart';
import '../core/managers/module_manager.dart';
import '../core/managers/navigation_manager.dart';
import '../core/services/shared_preferences.dart';
import '../core/widgets/instant_message_modal.dart';
import '../modules/connections_api_module/connections_api_module.dart';
import '../modules/dutch_game/screens/promotion/dutch_referral_bonus_celebration_screen.dart';
import '../modules/dutch_game/utils/dutch_game_helpers.dart';
import '../modules/login_module/login_module.dart';
import 'dev_logger.dart';
import 'referral_prefs.dart';

// ignore: constant_identifier_names — file-level gate for customlog (see Logging rules).
const bool LOGGING_SWITCH = true;

/// Deep-link → SharedPrefs list → ensure JWT session → POST /userauth/referrals/sync.
class ReferralSessionHelper {
  ReferralSessionHelper._();

  static bool _hooksRegistered = false;
  static bool _syncInFlight = false;

  static void registerHooks() {
    if (_hooksRegistered) return;
    _hooksRegistered = true;
    HooksManager().registerHookWithData('auth_login_complete', (_) {
      unawaited(ensureSessionAndSyncReferralCodes());
    }, priority: 25);
    // Deep link may arrive before navigator/context exists; retry once home is up.
    HooksManager().registerHookWithData('home_screen_main', (_) {
      unawaited(ensureSessionAndSyncReferralCodes());
    }, priority: 30);
    HooksManager().registerHookWithData('auth_login_success', (_) {
      unawaited(ensureSessionAndSyncReferralCodes());
    }, priority: 25);
  }

  /// Capture code from Universal/App Link and kick background sync.
  static void onDeepLinkCode(String rawCode) {
    unawaited(_captureAndSync(rawCode));
  }

  static Future<void> _captureAndSync(String rawCode) async {
    final code = await ReferralPrefs.appendCode(rawCode);
    if (LOGGING_SWITCH) {
      customlog('ReferralSessionHelper: captured code=${code ?? "(empty)"}');
    }
    if (code == null) return;
    await ensureSessionAndSyncReferralCodes();
  }

  /// Ensure guest/login session if needed, then sync all pending codes.
  static Future<bool> ensureSessionAndSyncReferralCodes() async {
    if (_syncInFlight) {
      if (LOGGING_SWITCH) {
        customlog('ReferralSessionHelper: sync already in flight');
      }
      return false;
    }

    final pending = await ReferralPrefs.getPendingCodes();
    if (pending.isEmpty) {
      return true;
    }

    _syncInFlight = true;
    try {
      final context = NavigationManager().navigatorKey.currentContext;
      if (context == null || !context.mounted) {
        if (LOGGING_SWITCH) {
          customlog('ReferralSessionHelper: no navigator context yet; keeping pending');
        }
        return false;
      }

      final sessionOk = await _ensureSession(context);
      if (!sessionOk) {
        if (LOGGING_SWITCH) {
          customlog('ReferralSessionHelper: session not ready; keeping pending=$pending');
        }
        return false;
      }

      return await _syncPendingCodes();
    } finally {
      _syncInFlight = false;
    }
  }

  static Future<bool> _ensureSession(BuildContext context) async {
    final loginModule = ModuleManager().getModuleByType<LoginModule>();
    if (loginModule == null) {
      return false;
    }

    if (await loginModule.hasValidToken()) {
      return true;
    }

    if (!context.mounted) {
      return false;
    }

    if (await _tryStoredAccountLogin(context, loginModule)) {
      return loginModule.hasValidToken();
    }

    if (!context.mounted) {
      return false;
    }

    final result = await loginModule.registerGuestUser(
      context: context,
      guestProvisionSource: 'referral',
    );
    if (result['success'] == null) {
      return false;
    }

    final loginReady = await DutchGameHelpers.waitForLoginStateReady();
    if (!loginReady) {
      return false;
    }

    await DutchGameHelpers.fetchAndUpdateInitData();
    return loginModule.hasValidToken();
  }

  /// Guest re-login or email/password from SharedPreferences (no Account UI).
  static Future<bool> _tryStoredAccountLogin(
    BuildContext context,
    LoginModule loginModule,
  ) async {
    final sharedPref = SharedPrefManager();
    await sharedPref.initialize();

    final isGuestAccount = sharedPref.getBool('is_guest_account') ?? false;
    if (isGuestAccount) {
      final username = sharedPref.getString('guest_username') ??
          sharedPref.getString('username');
      if (username == null || username.isEmpty) {
        return false;
      }
      final email = sharedPref.getString('guest_email') ??
          sharedPref.getString('email');
      final guestEmail = (email != null && email.isNotEmpty)
          ? email
          : 'guest_$username@guest.local';
      if (!guestEmail.toLowerCase().endsWith('@guest.local')) {
        return false;
      }
      final password = sharedPref.getString('password') ?? username;
      if (!context.mounted) {
        return false;
      }
      final result = await loginModule.loginUser(
        context: context,
        email: guestEmail,
        password: password,
      );
      if (result['success'] == null) {
        return false;
      }
      final loginReady = await DutchGameHelpers.waitForLoginStateReady();
      if (!loginReady) {
        return false;
      }
      await DutchGameHelpers.fetchAndUpdateInitData();
      return true;
    }

    final email = sharedPref.getString('email');
    final password = sharedPref.getString('password');
    if (email == null ||
        email.isEmpty ||
        password == null ||
        password.isEmpty) {
      return false;
    }

    if (!context.mounted) {
      return false;
    }

    final result = await loginModule.loginUser(
      context: context,
      email: email,
      password: password,
    );
    if (result['success'] == null) {
      return false;
    }

    final loginReady = await DutchGameHelpers.waitForLoginStateReady();
    if (!loginReady) {
      return false;
    }

    await DutchGameHelpers.fetchAndUpdateInitData();
    return true;
  }

  static Future<bool> _syncPendingCodes() async {
    final pending = await ReferralPrefs.getPendingCodes();
    if (pending.isEmpty) {
      return true;
    }

    final api = ModuleManager().getModuleByType<ConnectionsApiModule>();
    if (api == null) {
      return false;
    }

    if (LOGGING_SWITCH) {
      customlog('ReferralSessionHelper: POST /userauth/referrals/sync codes=$pending');
    }

    final response = await api.sendPostRequest('/userauth/referrals/sync', {
      'codes': pending,
    });

    if (response is! Map || response['success'] != true) {
      if (LOGGING_SWITCH) {
        customlog('ReferralSessionHelper: sync failed response=$response');
      }
      _showReferralFailureInstant(
        body:
            "Coins didn't transfer. Please try again.",
        event: 'referral_sync_failed',
      );
      return false;
    }

    final added = _stringList(response['added']);
    final already = _stringList(response['already_applied']);
    final rejectedRaw = response['rejected'];
    final rejectedCodes = <String>[];
    if (rejectedRaw is List) {
      for (final item in rejectedRaw) {
        if (item is Map && item['code'] != null) {
          rejectedCodes.add(ReferralPrefs.normalizeCode(item['code'].toString()));
        } else if (item is String) {
          rejectedCodes.add(ReferralPrefs.normalizeCode(item));
        }
      }
    }

    final removable = <String>{...added, ...already, ...rejectedCodes};
    await ReferralPrefs.removeCodes(removable);

    final coinsAwarded = (response['coins_awarded'] is num)
        ? (response['coins_awarded'] as num).toInt()
        : int.tryParse('${response['coins_awarded']}') ?? 0;

    if (LOGGING_SWITCH) {
      customlog(
        'ReferralSessionHelper: sync ok added=$added already=$already '
        'rejected=$rejectedCodes coins=$coinsAwarded',
      );
    }

    if (coinsAwarded > 0 || added.isNotEmpty) {
      await DutchGameHelpers.fetchAndUpdateInitData();
    }

    // Dedicated bonus celebration screen.
    if (coinsAwarded > 0) {
      _showReferralCoinsCelebration(coinsAwarded);
    } else if (already.isNotEmpty) {
      _showReferralFailureInstant(
        body: "You've already applied this offer.",
        event: 'referral_already_applied',
        data: {'codes': already},
      );
    } else if (rejectedCodes.isNotEmpty) {
      _showReferralFailureInstant(
        body:
            "Coins didn't transfer. Please try again.",
        event: 'referral_rejected',
        data: {'codes': rejectedCodes},
      );
    }

    return true;
  }

  /// Instant modal for unsuccessful referral coin transfer (existing notification UI).
  static void _showReferralFailureInstant({
    required String body,
    required String event,
    Map<String, dynamic>? data,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = NavigationManager().navigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) {
        if (LOGGING_SWITCH) {
          customlog(
            'ReferralSessionHelper: no context for failure instant event=$event',
          );
        }
        return;
      }
      if (LOGGING_SWITCH) {
        customlog('ReferralSessionHelper: showing failure instant event=$event');
      }
      unawaited(
        InstantMessageModal.showFrontendOnlyInstant(
          ctx,
          title: 'Bonus coins',
          body: body,
          data: {
            'event': event,
            ...?data,
          },
        ),
      );
    });
  }

  /// Fullscreen [DutchReferralBonusCelebrationScreen] after a successful award.
  static void _showReferralCoinsCelebration(int coinsAwarded) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = NavigationManager().navigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) {
        if (LOGGING_SWITCH) {
          customlog(
            'ReferralSessionHelper: no context for coins celebration coins=$coinsAwarded',
          );
        }
        return;
      }
      if (LOGGING_SWITCH) {
        customlog(
          'ReferralSessionHelper: showing bonus celebration for coins=$coinsAwarded',
        );
      }
      unawaited(
        Navigator.of(ctx, rootNavigator: true).push<void>(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => DutchReferralBonusCelebrationScreen(
              coinsAwarded: coinsAwarded,
            ),
          ),
        ),
      );
    });
  }

  static List<String> _stringList(dynamic value) {
    if (value is! List) return [];
    return value
        .map((e) => ReferralPrefs.normalizeCode(e.toString()))
        .where((c) => c.isNotEmpty)
        .toList();
  }
}
