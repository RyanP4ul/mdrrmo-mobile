import 'package:material_ui/material_ui.dart';

import '../../data/api/driver_service.api.dart';
import '../../ui/data_refresh.dart';
import '../../ui/kit.dart';
import '../../ui/page_loader.dart';
import '../record_details_screen.dart';
import 'responder_widgets.dart';
import 'service_schedule_card.dart';

class ServiceSchedulesScreen extends StatefulWidget {
  const ServiceSchedulesScreen({super.key, required this.api});

  final DriverApi api;

  @override
  State<ServiceSchedulesScreen> createState() => _ServiceSchedulesScreenState();
}

class _ServiceSchedulesScreenState extends State<ServiceSchedulesScreen> {
  List<Map<String, dynamic>> _schedules = const [];
  int? _next;
  bool _loading = false;
  bool _moreError = false;
  bool _activeOnly = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (_loading) return;
    final cursor = more ? _next : null;
    if (more && cursor == null) return;

    setState(() {
      _loading = true;
      _moreError = false;
      _error = null;
    });
    try {
      final page = await widget.api.fetchServiceSchedulesPage(before: cursor);
      if (!mounted) return;
      setState(() {
        _schedules = more
            ? [
                ..._schedules,
                ...page.items.where(
                  (schedule) =>
                      !_schedules.any((old) => old['id'] == schedule['id']),
                ),
              ]
            : page.items;
        _next = page.nextBefore;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _moreError = more;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isActive(Map<String, dynamic> schedule) {
    final status = '${schedule['status'] ?? ''}'.toLowerCase().trim();
    return const ['confirmed', 'en-route', 'on-scene'].contains(status);
  }

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    final visible = _activeOnly
        ? _schedules.where(_isActive).toList()
        : _schedules;

    return DataRefresh(
      onRefresh: _load,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.xxl,
          ),
          children: [
            ContentFrame(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ResponderHeading('Assigned services'),
                  Segmented<bool>(
                    value: _activeOnly,
                    onChanged: (value) => setState(() => _activeOnly = value),
                    options: const [
                      SegmentOption(false, 'All'),
                      SegmentOption(true, 'Active'),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (_loading && _schedules.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: Center(
                        child: CircularProgressIndicator(color: palette.brand),
                      ),
                    ),
                  if (visible.isEmpty && !_loading && _error == null)
                    Surface(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.xxl,
                      ),
                      child: Column(
                        children: [
                          Text(
                            _activeOnly
                                ? 'No active services'
                                : 'No assigned services',
                            textAlign: TextAlign.center,
                            style: MdrrmoTypography.titleMd.copyWith(
                              color: palette.textPrimary,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            _activeOnly
                                ? 'Switch to All to view completed or past trips.'
                                : 'Service assignments for your team appear here.',
                            textAlign: TextAlign.center,
                            style: MdrrmoTypography.bodySm.copyWith(
                              color: palette.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  for (var i = 0; i < visible.length; i++) ...[
                    if (i > 0) const SizedBox(height: AppSpacing.sm + 2),
                    ServiceScheduleCard(
                      schedule: visible[i],
                      onUpdated: _load,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => RecordDetailsScreen(
                            id: visible[i]['id'] as int,
                            driver: true,
                            schedule: true,
                            onChanged: _load,
                          ),
                        ),
                      ),
                    ),
                  ],
                  PageLoader(
                    hasMore: _next != null,
                    loading: _loading,
                    error: _error,
                    onLoad: () => _load(more: _error == null || _moreError),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
