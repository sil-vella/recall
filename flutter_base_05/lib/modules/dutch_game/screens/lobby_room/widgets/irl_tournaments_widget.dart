/// IRL Tournaments tab content: fetches active tournaments from the public API.
/// Shows name (or "Unnamed") and start_date when available; never shows created_at.

import 'package:flutter/material.dart';

import '../../../../../core/managers/module_manager.dart';
import '../../../../../modules/connections_api_module/connections_api_module.dart';
import '../../../../../utils/consts/theme_consts.dart';

/// One tournament entry from GET /public/dutch/get-tournaments-list
class _TournamentItem {
  final String id;
  final String? name;
  final DateTime? startDate;
  final DateTime? createdAt;

  _TournamentItem({required this.id, this.name, this.startDate, this.createdAt});
}

/// Widget that lists active IRL tournaments by name; shows start_date when available (never created_at).
/// Fetches on open (when [isExpanded] becomes true) and via "Get tournaments" button.
class IRLTournamentsWidget extends StatefulWidget {
  /// When true, the tab is visible; used to auto-fetch when opened.
  final bool isExpanded;

  const IRLTournamentsWidget({
    Key? key,
    required this.isExpanded,
  }) : super(key: key);

  @override
  State<IRLTournamentsWidget> createState() => _IRLTournamentsWidgetState();
}

class _IRLTournamentsWidgetState extends State<IRLTournamentsWidget> {
  List<_TournamentItem> _tournaments = [];
  bool _loading = false;
  bool _hasFetched = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.isExpanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fetchTournaments());
    }
  }

  @override
  void didUpdateWidget(covariant IRLTournamentsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isExpanded && !oldWidget.isExpanded) {
      _fetchTournaments();
    }
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

      final response = await api.sendGetRequest('/public/dutch/get-tournaments-list');
      if (!mounted) return;

      final map = response is Map ? response as Map<String, dynamic> : null;
      final success = map?['success'] == true;
      final list = map?['tournaments'] as List<dynamic>? ?? [];

      if (!success) {
        setState(() {
          _loading = false;
          _tournaments = [];
          _error = map?['error']?.toString() ?? 'Failed to load tournaments';
        });
        return;
      }

      final items = <_TournamentItem>[];
      for (final e in list) {
        final m = e is Map ? e as Map<String, dynamic> : null;
        if (m == null) continue;
        final id = m['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final nameRaw = m['name'];
        final name = (nameRaw != null && nameRaw.toString().trim().isNotEmpty)
            ? nameRaw.toString().trim()
            : null;
        DateTime? startDate;
        final startRaw = m['start_date'];
        if (startRaw != null) {
          if (startRaw is DateTime) {
            startDate = startRaw;
          } else if (startRaw is String && startRaw.trim().isNotEmpty) {
            startDate = DateTime.tryParse(startRaw.trim());
          }
        }
        DateTime? createdAt;
        final raw = m['created_at'];
        if (raw != null) {
          if (raw is DateTime) {
            createdAt = raw;
          } else if (raw is String) {
            createdAt = DateTime.tryParse(raw);
          }
        }
        items.add(_TournamentItem(id: id, name: name, startDate: startDate, createdAt: createdAt));
      }

      items.sort((a, b) {
        final ad = a.startDate ?? a.createdAt;
        final bd = b.startDate ?? b.createdAt;
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1;
        if (bd == null) return -1;
        return bd.compareTo(ad);
      });

      setState(() {
        _tournaments = items;
        _loading = false;
        _hasFetched = true;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  static String _formatDateOnly(DateTime? d) {
    if (d == null) return '—';
    return '${d.day} ${_month(d.month)} ${d.year}';
  }

  static String _month(int m) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[m.clamp(1, 12) - 1];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: AppPadding.smallPadding.left),
      decoration: BoxDecoration(
        color: AppColors.widgetContainerBackground,
        borderRadius: BorderRadius.circular(AppBorderRadius.large),
      ),
      child: Padding(
        padding: AppPadding.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Active IRL tournaments',
              style: AppTextStyles.headingSmall().copyWith(color: AppColors.white),
            ),
            SizedBox(height: AppPadding.defaultPadding.top),
            ElevatedButton.icon(
              onPressed: _loading ? null : _fetchTournaments,
              icon: _loading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.textOnAccent,
                      ),
                    )
                  : const Icon(Icons.refresh),
              label: Text(_loading ? 'Loading…' : 'Get tournaments'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentColor,
                foregroundColor: AppColors.textOnAccent,
              ),
            ),
            if (_error != null) ...[
              SizedBox(height: AppPadding.smallPadding.top),
              Text(
                _error!,
                style: AppTextStyles.bodySmall().copyWith(color: AppColors.errorColor),
              ),
            ],
            if (_tournaments.isNotEmpty) ...[
              SizedBox(height: AppPadding.defaultPadding.top),
              ..._tournaments.map((t) {
                final displayName = (t.name != null && t.name!.isNotEmpty)
                    ? t.name!
                    : 'Unnamed';
                final startDateText = t.startDate != null
                    ? _formatDateOnly(t.startDate)
                    : null;
                return Padding(
                  padding: EdgeInsets.only(top: AppPadding.smallPadding.top),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          displayName,
                          style: AppTextStyles.bodyMedium().copyWith(color: AppColors.white),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (startDateText != null)
                        Text(
                          startDateText,
                          style: AppTextStyles.bodySmall().copyWith(color: AppColors.textSecondary),
                        ),
                    ],
                  ),
                );
              }),
            ] else if (_hasFetched && !_loading && _error == null && _tournaments.isEmpty) ...[
              SizedBox(height: AppPadding.smallPadding.top),
              Text(
                'No active tournaments.',
                style: AppTextStyles.bodyMedium().copyWith(color: AppColors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
