import 'package:flutter/material.dart';

import '../core/managers/module_manager.dart';
import '../core/services/shared_preferences.dart';
import '../modules/dutch_game/utils/dutch_game_helpers.dart';
import '../modules/login_module/login_module.dart';

/// Ensures a JWT-backed session before native IAP server verify, without email signup.
class IapSessionHelper {
  IapSessionHelper._();

  /// [guestProvisionSource] is passed to [LoginModule.registerGuestUser] analytics
  /// (`iap_coins`, `iap_premium`, etc.).
  static Future<bool> ensureSessionForPurchase({
    required BuildContext context,
    required String guestProvisionSource,
  }) async {
    final loginModule = ModuleManager().getModuleByType<LoginModule>();
    if (loginModule == null) {
      return false;
    }

    if (await loginModule.hasValidToken()) {
      return true;
    }

    if (await _tryGuestRelogin(context, loginModule)) {
      return loginModule.hasValidToken();
    }

    final result = await loginModule.registerGuestUser(
      context: context,
      guestProvisionSource: guestProvisionSource,
    );

    if (result['success'] == null) {
      return false;
    }

    final loginReady = await DutchGameHelpers.waitForLoginStateReady();
    if (!loginReady) {
      return false;
    }

    await DutchGameHelpers.fetchAndUpdateUserDutchGameData();
    return loginModule.hasValidToken();
  }

  /// Mirrors Account screen guest login: prefs `guest_email` + username-as-password.
  static Future<bool> _tryGuestRelogin(
    BuildContext context,
    LoginModule loginModule,
  ) async {
    final sharedPref = SharedPrefManager();
    await sharedPref.initialize();

    final isGuestAccount = sharedPref.getBool('is_guest_account') ?? false;
    if (!isGuestAccount) {
      return false;
    }

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

    await DutchGameHelpers.fetchAndUpdateUserDutchGameData();
    return true;
  }
}
