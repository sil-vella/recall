/// Admin Tournaments screen: fetch tournaments via API, filter by status/type/format, list results.
/// Tapping a tournament opens a detail section below with full data and matches (schema from playbook).
/// Route: /admin/tournaments (registered in Dutch module; drawerTitle: null).

import 'package:flutter/material.dart';

import '../../../../../core/00_base/screen_base.dart';
import '../../../../../tools/logging/logger.dart';
import '../../../../../core/managers/module_manager.dart';
import '../../../../../modules/connections_api_module/connections_api_module.dart';
import '../../../../../modules/user_management_module/user_management_module.dart';
import '../../../../../utils/consts/theme_consts.dart';
import '../../managers/validated_event_emitter.dart';
import '../../utils/dutch_game_helpers.dart';

/// Max number of tournament rows visible before scrolling.
const int _kMaxVisibleTournamentRows = 5;

/// Approximate height of one tournament list row for scroll area.
const double _kTournamentRowHeight = 80.0;

class AdminTournamentsScreen extends BaseScreen {
  const AdminTournamentsScreen({Key? key}) : super(key: key);

  @override
  BaseScreenState<AdminTournamentsScreen> createState() => _AdminTournamentsScreenState();

  @override
  String computeTitle(BuildContext context) => 'Admin Tournaments';
}

class _AdminTournamentsScreenState extends BaseScreenState<AdminTournamentsScreen> {
  static const String _all = 'All';
  static const bool LOGGING_SWITCH = false; // Tournament match create flow — see .cursor/rules/enable-logging-switch.mdc
  static final Logger _logger = Logger();

  /// Full tournament docs from API (id, name, status, type, format, start_date, matches, ...).
  List<Map<String, dynamic>> _allTournaments = [];
  bool _loading = false;
  String? _error;

  String _filterStatus = _all;
  String _filterType = _all;
  String _filterFormat = _all;

  /// Selected tournament id (opens detail section below list).
  String? _selectedTournamentId;

  /// Match index of the expanded match in the detail section (only one open at a time). Null = none expanded.
  dynamic _expandedMatchIndex;

  /// Room IDs for which the Start Match button is enabled (5 seconds after successful Notify Players).
  final Set<String> _startMatchEnabledRoomIds = {};
  /// Room IDs for which a start_match request is in progress (disable button to avoid double-send).
  final Set<String> _startMatchInProgressRoomIds = {};

  List<Map<String, dynamic>> get _filteredTournaments {
    return _allTournaments.where((t) {
      final status = (t['status'] as String? ?? '').toString().trim().toLowerCase();
      final type = (t['type'] as String? ?? '').toString().trim().toLowerCase();
      final format = (t['format'] as String? ?? '').toString().trim().toLowerCase();
      if (_filterStatus != _all && status != _filterStatus.toLowerCase()) return false;
      if (_filterType != _all && type != _filterType.toLowerCase()) return false;
      if (_filterFormat != _all && format != _filterFormat.toLowerCase()) return false;
      return true;
    }).toList();
  }

  Map<String, dynamic>? get _selectedTournament {
    if (_selectedTournamentId == null) return null;
    for (final t in _filteredTournaments) {
      if ((t['id']?.toString() ?? '') == _selectedTournamentId) return t;
    }
    return null;
  }

  Future<void> _fetchTournaments() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final moduleManager = ModuleManager();
      final api = moduleManager.getModuleByType<ConnectionsApiModule>();
      if (api == null) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'API not available';
          });
        }
        return;
      }

      // Admin-only endpoint (JWT required): returns all tournaments with type, format, status.
      final response = await api.sendGetRequest('/userauth/dutch/get-tournaments');
      if (!mounted) return;

      final map = response is Map ? response as Map<String, dynamic> : null;
      final success = map?['success'] == true;
      final list = map?['tournaments'] as List<dynamic>? ?? [];

      if (!success) {
        setState(() {
          _loading = false;
          _allTournaments = [];
          _error = map?['error']?.toString() ?? 'Failed to load tournaments';
        });
        return;
      }

      final items = <Map<String, dynamic>>[];
      for (final e in list) {
        final m = e is Map ? e as Map<String, dynamic> : null;
        if (m == null) continue;
        final id = m['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        items.add(m);
      }

      setState(() {
        _allTournaments = items;
        _loading = false;
        _error = null;
        if (_selectedTournamentId != null && !items.any((t) => (t['id']?.toString() ?? '') == _selectedTournamentId)) {
          _selectedTournamentId = null;
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error: $e',
              style: AppTextStyles.bodyMedium().copyWith(color: AppColors.white),
            ),
            backgroundColor: AppColors.errorColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  static String _formatDate(DateTime? d) {
    if (d == null) return '—';
    return '${d.day} ${_month(d.month)} ${d.year}';
  }

  static String _month(int m) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[m.clamp(1, 12) - 1];
  }

  @override
  Widget buildContent(BuildContext context) {
    return SingleChildScrollView(
      padding: AppPadding.screenPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Get Tournaments button
          Container(
            decoration: BoxDecoration(
              color: AppColors.primaryColor,
              borderRadius: BorderRadius.circular(AppBorderRadius.large),
              boxShadow: [
                BoxShadow(
                  color: AppColors.black.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _loading ? null : _fetchTournaments,
                borderRadius: BorderRadius.circular(AppBorderRadius.large),
                child: Container(
                  padding: AppPadding.defaultPadding,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_loading)
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.textOnPrimary,
                          ),
                        )
                      else
                        Icon(Icons.refresh, color: AppColors.textOnPrimary),
                      SizedBox(width: AppPadding.smallPadding.left),
                      Text(
                        _loading ? 'Loading…' : 'Get Tournaments',
                        style: AppTextStyles.headingSmall().copyWith(
                          color: AppColors.textOnPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_error != null) ...[
            SizedBox(height: AppPadding.defaultPadding.top),
            Text(
              _error!,
              style: AppTextStyles.bodySmall().copyWith(color: AppColors.errorColor),
            ),
          ],
          SizedBox(height: AppPadding.largePadding.top),
          // Filters
          Text('Filters', style: AppTextStyles.label().copyWith(color: AppColors.textOnPrimary)),
          SizedBox(height: AppPadding.smallPadding.top),
          Wrap(
            spacing: AppPadding.smallPadding.left,
            runSpacing: AppPadding.smallPadding.top,
            children: [
              _buildFilterChip('Status', _filterStatus, ['All', 'Pending', 'Active', 'Complete'], (v) {
                setState(() => _filterStatus = v == 'All' ? _all : v);
              }),
              _buildFilterChip('Type', _filterType, ['All', 'IRL', 'Online'], (v) {
                setState(() => _filterType = v == 'All' ? _all : v);
              }),
              _buildFilterChip('Format', _filterFormat, ['All', 'League', 'Cup'], (v) {
                setState(() => _filterFormat = v == 'All' ? _all : v);
              }),
            ],
          ),
          SizedBox(height: AppPadding.largePadding.top),
          // List
          Container(
            decoration: BoxDecoration(
              color: AppColors.widgetContainerBackground,
              borderRadius: BorderRadius.circular(AppBorderRadius.large),
            ),
            padding: AppPadding.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Tournaments',
                  style: AppTextStyles.headingSmall().copyWith(color: AppColors.textOnPrimary),
                ),
                SizedBox(height: AppPadding.defaultPadding.top),
                if (_allTournaments.isEmpty && !_loading) ...[
                  Text(
                    _error != null ? 'Fix the error and tap Get Tournaments.' : 'Tap "Get Tournaments" to load list.',
                    style: AppTextStyles.bodyMedium().copyWith(color: AppColors.textOnPrimary),
                  ),
                ] else if (_filteredTournaments.isEmpty) ...[
                  Text(
                    'No tournaments match the filters.',
                    style: AppTextStyles.bodyMedium().copyWith(color: AppColors.textOnPrimary),
                  ),
                ] else
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: _kMaxVisibleTournamentRows * _kTournamentRowHeight,
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _filteredTournaments.length,
                      separatorBuilder: (_, __) => SizedBox(height: AppPadding.smallPadding.top),
                      itemBuilder: (context, index) {
                        final t = _filteredTournaments[index];
                        final id = t['id']?.toString() ?? '';
                        final name = (t['name']?.toString() ?? '').trim().isNotEmpty
                            ? (t['name']?.toString() ?? '').trim()
                            : id;
                        final status = t['status']?.toString() ?? '—';
                        final type = t['type']?.toString() ?? '—';
                        final format = t['format']?.toString() ?? '—';
                        final startDate = _parseDate(t['start_date']);
                        final isSelected = _selectedTournamentId == id;
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _selectedTournamentId = _selectedTournamentId == id ? null : id;
                                _expandedMatchIndex = null;
                              });
                            },
                            borderRadius: BorderRadius.circular(AppBorderRadius.medium),
                            child: Container(
                              padding: AppPadding.cardPadding,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.accentColor.withOpacity(0.25)
                                    : AppColors.cardVariant,
                                borderRadius: BorderRadius.circular(AppBorderRadius.medium),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    name,
                                    style: AppTextStyles.bodyMedium().copyWith(
                                      color: AppColors.textOnPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  SizedBox(height: AppPadding.smallPadding.top),
                                  Row(
                                    children: [
                                      _labelValue('Status', status),
                                      SizedBox(width: AppPadding.defaultPadding.left),
                                      _labelValue('Type', type),
                                      SizedBox(width: AppPadding.defaultPadding.left),
                                      _labelValue('Format', format),
                                      SizedBox(width: AppPadding.defaultPadding.left),
                                      _labelValue('Start', _formatDate(startDate)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          if (_selectedTournament != null) ...[
            SizedBox(height: AppPadding.largePadding.top),
            _buildTournamentDetailSection(_selectedTournament!),
          ],
        ],
      ),
    );
  }

  /// Detail section: full tournament data + matches list with Add match and per-match Invite.
  Widget _buildTournamentDetailSection(Map<String, dynamic> tournament) {
    final matches = tournament['matches'] as List<dynamic>? ?? [];
    return Container(
      decoration: BoxDecoration(
        color: AppColors.widgetContainerBackground,
        borderRadius: BorderRadius.circular(AppBorderRadius.large),
      ),
      padding: AppPadding.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Tournament details',
                style: AppTextStyles.headingSmall().copyWith(color: AppColors.textOnPrimary),
              ),
              IconButton(
                icon: Icon(Icons.refresh, color: AppColors.textOnPrimary, size: 22),
                onPressed: _loading
                    ? null
                    : () async {
                        await _fetchTournaments();
                      },
                tooltip: 'Refresh from DB',
              ),
            ],
          ),
          SizedBox(height: AppPadding.defaultPadding.top),
          _buildDetailRow('ID', tournament['id']?.toString() ?? '—'),
          _buildDetailRow('Tournament ID', tournament['tournament_id']?.toString() ?? '—'),
          _buildDetailRow('Name', tournament['name']?.toString() ?? '—'),
          _buildDetailRow('Status', tournament['status']?.toString() ?? '—'),
          _buildDetailRow('Type', tournament['type']?.toString() ?? '—'),
          _buildDetailRow('Format', tournament['format']?.toString() ?? '—'),
          _buildDetailRow('Start date', _formatDate(_parseDate(tournament['start_date']))),
          if (tournament['created_at'] != null)
            _buildDetailRow('Created', _formatDate(_parseDate(tournament['created_at']))),
          if (tournament['updated_at'] != null)
            _buildDetailRow('Updated', _formatDate(_parseDate(tournament['updated_at']))),
          SizedBox(height: AppPadding.largePadding.top),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Matches',
                style: AppTextStyles.headingSmall().copyWith(color: AppColors.textOnPrimary),
              ),
              TextButton.icon(
                onPressed: () => _showMatchUserPickerDialog(
                  context,
                  tournamentId: tournament['id']?.toString(),
                  matchIndex: null,
                  isAddMatch: true,
                  onSaved: _fetchTournaments,
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add match'),
              ),
            ],
          ),
          SizedBox(height: AppPadding.smallPadding.top),
          if (matches.isEmpty)
            Text(
              'No matches yet.',
              style: AppTextStyles.bodyMedium().copyWith(color: AppColors.textSecondary),
            )
          else
            ...matches.asMap().entries.map((entry) {
              final m = entry.value is Map ? entry.value as Map<String, dynamic> : null;
              if (m == null) return SizedBox(height: AppPadding.smallPadding.top);
              final matchIndex = m['match_index'];
              final isExpanded = _expandedMatchIndex == matchIndex;
              return Padding(
                padding: EdgeInsets.only(bottom: AppPadding.smallPadding.top),
                child: _buildMatchCard(
                  context,
                  m,
                  tournament['id']?.toString(),
                  tournamentType: tournament['type']?.toString(),
                  tournamentFormat: tournament['format']?.toString(),
                  isExpanded: isExpanded,
                  onTap: () {
                    setState(() {
                      if (_expandedMatchIndex == matchIndex) {
                        _expandedMatchIndex = null;
                      } else {
                        _expandedMatchIndex = matchIndex;
                      }
                    });
                  },
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: AppPadding.smallPadding.top / 2),
      child: Text(
        '$label: $value',
        style: AppTextStyles.bodySmall().copyWith(color: AppColors.textOnPrimary),
      ),
    );
  }

  /// One match card (accordion): tap header to expand/collapse. Only one match open at a time is enforced by caller.
  Widget _buildMatchCard(
    BuildContext context,
    Map<String, dynamic> match,
    String? tournamentId, {
    String? tournamentType,
    String? tournamentFormat,
    required bool isExpanded,
    required VoidCallback onTap,
  }) {
    final matchId = match['match_id']?.toString() ?? '—';
    final status = match['status']?.toString() ?? '—';
    final roomId = match['room_id']?.toString() ?? '—';
    final roomIdBlank = roomId.isEmpty || roomId == '—';
    final winner = match['winner']?.toString() ?? '—';
    final startDate = _formatDate(_parseDate(match['start_date']));
    final players = match['players'] as List<dynamic>? ?? [];
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardVariant,
        borderRadius: BorderRadius.circular(AppBorderRadius.medium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppBorderRadius.medium),
            child: Padding(
              padding: AppPadding.cardPadding,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Match: $matchId',
                      style: AppTextStyles.bodyMedium().copyWith(
                        color: AppColors.textOnPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.textOnPrimary,
                    size: 24,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            Divider(height: 1, color: AppColors.borderDefault),
            Padding(
              padding: AppPadding.cardPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDetailRow('Status', status),
                  if (roomIdBlank)
                    Padding(
                      padding: EdgeInsets.only(bottom: AppPadding.smallPadding.top / 2),
                      child: Row(
                        children: [
                          Text(
                            'Room ID: ',
                            style: AppTextStyles.bodySmall().copyWith(color: AppColors.textOnPrimary),
                          ),
                          TextButton(
                            onPressed: () async {
                              if (LOGGING_SWITCH) {
                                _logger.info('🏟 Admin Tournaments: Create room pressed — tournamentId=${tournamentId ?? "null"} matchId=$matchId');
                              }
                              final tt = tournamentType?.trim() ?? '';
                              final tf = tournamentFormat?.trim() ?? '';
                              final result = await DutchGameHelpers.createRoom(
                                addCreatorToRoom: false,
                                maxPlayers: 4,
                                minPlayers: 2,
                                autoStart: false,
                                permission: 'public',
                                gameType: 'classic',
                                isTournament: true,
                                isCoinRequired: false,
                                tournamentData: {
                                  'tournament_id': tournamentId ?? '',
                                  'match_id': matchId,
                                  if (tt.isNotEmpty) 'type': tt,
                                  if (tf.isNotEmpty) 'format': tf,
                                },
                              );
                              if (!context.mounted) return;
                              final success = result['success'] == true;
                              if (LOGGING_SWITCH) {
                                _logger.info('🏟 Admin Tournaments: Create room result — success=$success room_id=${result['room_id']} error=${result['error']}');
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    success ? (result['room_id']?.toString() ?? 'Room created') : (result['error']?.toString() ?? 'Failed to create room'),
                                    style: AppTextStyles.bodyMedium().copyWith(color: AppColors.white),
                                  ),
                                  backgroundColor: success ? AppColors.primaryColor : AppColors.errorColor,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                            child: Text(
                              'Create room',
                              style: AppTextStyles.bodySmall().copyWith(color: AppColors.accentColor),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    _buildDetailRow('Room ID', roomId),
                  _buildDetailRow('Winner', winner),
                  _buildDetailRow('Start date', startDate),
                  if (players.isNotEmpty) ...[
                    SizedBox(height: AppPadding.smallPadding.top),
                    Text(
                      'Players',
                      style: AppTextStyles.label().copyWith(color: AppColors.textOnPrimary),
                    ),
                    ...players.map((p) {
                      final map = p is Map ? p as Map<String, dynamic> : null;
                      if (map == null) return const SizedBox.shrink();
                      final userId = map['user_id']?.toString() ?? '—';
                      final username = map['username']?.toString() ?? '—';
                      final email = map['email']?.toString() ?? '—';
                      final points = map['points']?.toString() ?? '—';
                      final cardsLeft = map['number_of_cards_left'];
                      final cardsStr = cardsLeft is List
                          ? '${cardsLeft.length} cards'
                          : (cardsLeft?.toString() ?? '—');
                      return Padding(
                        padding: EdgeInsets.only(left: AppPadding.defaultPadding.left, top: 4),
                        child: Text(
                          'user_id: $userId, username: $username, email: $email, points: $points, cards_left: $cardsStr',
                          style: AppTextStyles.caption().copyWith(color: AppColors.textOnPrimary),
                        ),
                      );
                    }),
                  ],
                  SizedBox(height: AppPadding.smallPadding.top),
                  Row(
                    children: [
                      TextButton(
                        onPressed: roomIdBlank
                            ? null
                            : () async {
                                final userIds = <String>[];
                                for (final p in players) {
                                  final map = p is Map ? p as Map<String, dynamic> : null;
                                  if (map == null) continue;
                                  final uid = (map['user_id']?.toString() ?? '').trim();
                                  if (uid.isNotEmpty && uid != '—') {
                                    userIds.add(uid);
                                  }
                                }
                                if (userIds.isEmpty) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'No players to notify',
                                          style: AppTextStyles.bodyMedium().copyWith(color: AppColors.white),
                                        ),
                                        backgroundColor: AppColors.warningColor,
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
                                  return;
                                }
                                final api = ModuleManager().getModuleByType<ConnectionsApiModule>();
                                if (api == null) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'API not available',
                                          style: AppTextStyles.bodyMedium().copyWith(color: AppColors.white),
                                        ),
                                        backgroundColor: AppColors.errorColor,
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
                                  return;
                                }
                                final body = <String, dynamic>{
                                  'user_ids': userIds,
                                  'match_id': matchId,
                                  'room_id': roomId,
                                  'title': 'Tournament match invite',
                                  'body': 'You are invited to join the match. Room ID: $roomId',
                                };
                                try {
                                  final response = await api.sendPostRequest(
                                    '/userauth/dutch/invite-players-to-match',
                                    body,
                                  );
                                  if (!context.mounted) return;
                                  final map = response is Map ? response as Map<String, dynamic> : null;
                                  final success = map?['success'] == true;
                                  final notified = map?['notified'] as int? ?? 0;
                                  final requested = map?['requested'] as int? ?? 0;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        success
                                            ? 'Notified $notified of $requested player(s). Start Match enabled in 5s.'
                                            : (map?['error']?.toString() ?? 'Failed to notify players'),
                                        style: AppTextStyles.bodyMedium().copyWith(color: AppColors.white),
                                      ),
                                      backgroundColor: success ? AppColors.successColor : AppColors.errorColor,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                  if (success && roomId.isNotEmpty) {
                                    Future.delayed(const Duration(seconds: 5), () {
                                      if (mounted) {
                                        setState(() {
                                          _startMatchEnabledRoomIds.add(roomId);
                                        });
                                      }
                                    });
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Error: $e',
                                          style: AppTextStyles.bodyMedium().copyWith(color: AppColors.white),
                                        ),
                                        backgroundColor: AppColors.errorColor,
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
                                }
                              },
                        style: TextButton.styleFrom(
                          backgroundColor: roomIdBlank ? AppColors.disabledColor : AppColors.accentColor,
                          foregroundColor: roomIdBlank ? AppColors.textSecondary : AppColors.textOnAccent,
                          padding: AppPadding.cardPadding,
                          shape: RoundedRectangleBorder(
                            borderRadius: AppBorderRadius.mediumRadius,
                          ),
                        ),
                        child: Text(
                          'Notify Players',
                          style: AppTextStyles.buttonText().copyWith(
                            color: roomIdBlank ? AppColors.textSecondary : AppColors.textOnAccent,
                          ),
                        ),
                      ),
                      SizedBox(width: AppPadding.smallPadding.left),
                      TextButton(
                        onPressed: (roomIdBlank || !_startMatchEnabledRoomIds.contains(roomId) || _startMatchInProgressRoomIds.contains(roomId))
                            ? null
                            : () async {
                                setState(() {
                                  _startMatchInProgressRoomIds.add(roomId);
                                });
                                try {
                                  final result = await DutchGameEventEmitter.instance.emit(
                                    eventType: 'start_match',
                                    data: {'game_id': roomId},
                                  );
                                  if (!mounted) return;
                                  final ok = result['success'] == true;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        ok ? 'Start match sent for room $roomId' : (result['error']?.toString() ?? 'Failed to start match'),
                                        style: AppTextStyles.bodyMedium().copyWith(color: AppColors.white),
                                      ),
                                      backgroundColor: ok ? AppColors.successColor : AppColors.errorColor,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                  if (ok) {
                                    _startMatchEnabledRoomIds.remove(roomId);
                                  }
                                } finally {
                                  if (mounted) {
                                    setState(() {
                                      _startMatchInProgressRoomIds.remove(roomId);
                                    });
                                  }
                                }
                              },
                        style: TextButton.styleFrom(
                          backgroundColor: (roomIdBlank || !_startMatchEnabledRoomIds.contains(roomId) || _startMatchInProgressRoomIds.contains(roomId))
                              ? AppColors.disabledColor
                              : AppColors.successColor,
                          foregroundColor: (roomIdBlank || !_startMatchEnabledRoomIds.contains(roomId) || _startMatchInProgressRoomIds.contains(roomId))
                              ? AppColors.textSecondary
                              : AppColors.textOnAccent,
                          padding: AppPadding.cardPadding,
                          shape: RoundedRectangleBorder(
                            borderRadius: AppBorderRadius.mediumRadius,
                          ),
                        ),
                        child: Text(
                          _startMatchInProgressRoomIds.contains(roomId) ? 'Starting…' : 'Start Match',
                          style: AppTextStyles.buttonText().copyWith(
                            color: (roomIdBlank || !_startMatchEnabledRoomIds.contains(roomId) || _startMatchInProgressRoomIds.contains(roomId))
                                ? AppColors.textSecondary
                                : AppColors.textOnAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String && value.trim().isNotEmpty) return DateTime.tryParse(value.trim());
    return null;
  }

  /// Shows dialog to pick users (search by username/email) and optional date. Save calls add-tournament-match or update-tournament-match.
  void _showMatchUserPickerDialog(
    BuildContext context, {
    required String? tournamentId,
    required dynamic matchIndex,
    required bool isAddMatch,
    required VoidCallback onSaved,
  }) {
    if (tournamentId == null || tournamentId.isEmpty) return;
    final moduleManager = ModuleManager();
    final api = moduleManager.getModuleByType<ConnectionsApiModule>();
    final userModule = moduleManager.getModuleByType<UserManagementModule>();
    if (api == null || userModule == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text('API or user search not available'), backgroundColor: AppColors.errorColor, behavior: SnackBarBehavior.floating),
      );
      return;
    }

    String searchQuery = '';
    List<Map<String, dynamic>> searchResults = [];
    List<Map<String, dynamic>> selectedUsers = [];
    final dateController = TextEditingController();
    bool searching = false;
    bool saving = false;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.widgetContainerBackground,
              title: Text(isAddMatch ? 'Add match' : 'Invite to match', style: AppTextStyles.headingSmall().copyWith(color: AppColors.textOnPrimary)),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 400,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(isAddMatch ? 'Date (optional)' : 'Match date (optional)', style: AppTextStyles.label().copyWith(color: AppColors.textOnPrimary)),
                      SizedBox(height: 4),
                      TextField(
                        controller: dateController,
                        decoration: InputDecoration(
                          hintText: 'YYYY-MM-DD',
                          hintStyle: AppTextStyles.bodyMedium().copyWith(color: AppColors.textSecondary),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppBorderRadius.medium)),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        style: AppTextStyles.bodyMedium().copyWith(color: AppColors.textOnPrimary),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      SizedBox(height: AppPadding.defaultPadding.top),
                      Text('Search users (username or email)', style: AppTextStyles.label().copyWith(color: AppColors.textOnPrimary)),
                      SizedBox(height: 4),
                      TextField(
                        decoration: InputDecoration(
                          hintText: 'Min 3 characters – results update as you type',
                          hintStyle: AppTextStyles.bodyMedium().copyWith(color: AppColors.textSecondary),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppBorderRadius.medium)),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          suffixIcon: searching
                              ? Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentColor)),
                                )
                              : null,
                        ),
                        style: AppTextStyles.bodyMedium().copyWith(color: AppColors.textOnPrimary),
                        onChanged: (v) {
                          setDialogState(() {
                            searchQuery = v;
                            if (v.trim().length < 3) {
                              searchResults = [];
                            }
                          });
                          if (v.trim().length >= 3) {
                            final q = v.trim();
                            setDialogState(() => searching = true);
                            Future.delayed(const Duration(milliseconds: 350), () async {
                              final list = await userModule.searchByUsername(q, limit: 20);
                              setDialogState(() {
                                if (searchQuery.trim() == q) searchResults = list;
                                searching = false;
                              });
                            });
                          }
                        },
                      ),
                      if (searchResults.isNotEmpty) ...[
                        SizedBox(height: 8),
                        Text('Results', style: AppTextStyles.caption().copyWith(color: AppColors.textOnPrimary)),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 120),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: searchResults.length,
                            itemBuilder: (_, i) {
                              final u = searchResults[i];
                              final uid = u['user_id']?.toString() ?? u['_id']?.toString() ?? '';
                              final username = u['username']?.toString() ?? '';
                              final email = u['email']?.toString() ?? '';
                              final already = selectedUsers.any((s) => (s['user_id']?.toString() ?? s['_id']?.toString()) == uid);
                              return ListTile(
                                title: Text(username.isNotEmpty ? username : uid, style: AppTextStyles.bodySmall().copyWith(color: AppColors.textOnPrimary)),
                                subtitle: email.isNotEmpty ? Text(email, style: AppTextStyles.caption().copyWith(color: AppColors.textSecondary)) : null,
                                trailing: already ? Icon(Icons.check, color: AppColors.accentColor, size: 20) : Icon(Icons.add, color: AppColors.accentColor, size: 20),
                                onTap: already
                                    ? null
                                    : () {
                                        setDialogState(() {
                                          selectedUsers.add({...u, 'user_id': uid});
                                        });
                                      },
                              );
                            },
                          ),
                        ),
                      ],
                      if (selectedUsers.isNotEmpty) ...[
                        SizedBox(height: 12),
                        Text('Invited', style: AppTextStyles.caption().copyWith(color: AppColors.textOnPrimary)),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: selectedUsers.map((u) {
                            final uid = u['user_id']?.toString() ?? '';
                            final label = u['username']?.toString() ?? u['email']?.toString() ?? uid;
                            return Chip(
                              label: Text(label, style: AppTextStyles.caption().copyWith(color: AppColors.textOnPrimary)),
                              deleteIcon: Icon(Icons.close, size: 16, color: AppColors.textOnPrimary),
                              onDeleted: () => setDialogState(() => selectedUsers.removeWhere((e) => (e['user_id']?.toString()) == uid)),
                              backgroundColor: AppColors.cardVariant,
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.of(context).pop(),
                  child: Text('Cancel', style: AppTextStyles.bodyMedium().copyWith(color: AppColors.textOnPrimary)),
                ),
                FilledButton(
                  onPressed: saving || (isAddMatch && selectedUsers.isEmpty)
                      ? null
                      : () async {
                          setDialogState(() => saving = true);
                          final userIds = selectedUsers.map((u) => u['user_id']?.toString() ?? '').where((id) => id.isNotEmpty).toList();
                          final body = <String, dynamic>{
                            'tournament_id': tournamentId,
                            'user_ids': userIds,
                          };
                          if (isAddMatch) {
                            final d = dateController.text.trim();
                            if (d.isNotEmpty) body['start_date'] = d;
                          } else {
                            body['match_index'] = matchIndex;
                            final d = dateController.text.trim();
                            if (d.isNotEmpty) body['start_date'] = d;
                          }
                          final endpoint = isAddMatch ? '/userauth/dutch/add-tournament-match' : '/userauth/dutch/update-tournament-match';
                          try {
                            final response = await api.sendPostRequest(endpoint, body);
                            if (!mounted) return;
                            final map = response is Map ? response as Map<String, dynamic> : null;
                            if (map?['success'] == true) {
                              Navigator.of(context).pop();
                              onSaved();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(map?['message'] ?? 'Saved'), backgroundColor: AppColors.primaryColor, behavior: SnackBarBehavior.floating),
                              );
                            } else {
                              setDialogState(() => saving = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(map?['error'] ?? 'Failed to save'), backgroundColor: AppColors.errorColor, behavior: SnackBarBehavior.floating),
                              );
                            }
                          } catch (e) {
                            if (mounted) setDialogState(() => saving = false);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.errorColor, behavior: SnackBarBehavior.floating),
                              );
                            }
                          }
                        },
                  child: saving
                      ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textOnPrimary))
                      : Text('Save', style: AppTextStyles.bodyMedium().copyWith(color: AppColors.textOnPrimary)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildFilterChip(String label, String current, List<String> options, ValueChanged<String> onSelected) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AppTextStyles.caption().copyWith(color: AppColors.textOnPrimary)),
        SizedBox(height: AppPadding.smallPadding.top / 2),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: options.map((opt) {
            final value = opt == 'All' ? _all : opt;
            final selected = current == value;
            return FilterChip(
              label: Text(
                opt,
                style: AppTextStyles.caption().copyWith(
                  color: selected ? AppColors.textOnAccent : AppColors.textOnPrimary,
                ),
              ),
              selected: selected,
              onSelected: (_) => onSelected(opt),
              selectedColor: AppColors.accentColor.withOpacity(0.3),
              checkmarkColor: AppColors.textOnAccent,
              backgroundColor: AppColors.widgetContainerBackground,
              side: BorderSide(color: AppColors.borderDefault),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _labelValue(String label, String value) {
    return Text(
      '$label: $value',
      style: AppTextStyles.caption().copyWith(color: AppColors.textOnPrimary),
    );
  }
}
