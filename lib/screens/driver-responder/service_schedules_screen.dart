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

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
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
                  const ResponderHeading(
                    'Assigned services',
                    subtitle: 'Service requests assigned to your response team.',
                  ),
                  if (_loading && _schedules.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Center(
                        child: CircularProgressIndicator(color: palette.brand),
                      ),
                    ),
                  if (_schedules.isEmpty && !_loading && _error == null)
                    const ResponderEmptyState(
                      icon: AppIcons.stethoscope,
                      title: 'No assigned services',
                      message:
                          'New service assignments for your response team will appear here.',
                    ),
                  for (final schedule in _schedules)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ServiceScheduleCard(
                        schedule: schedule,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => RecordDetailsScreen(
                              id: schedule['id'] as int,
                              driver: true,
                              schedule: true,
                              onChanged: _load,
                            ),
                          ),
                        ),
                      ),
                    ),
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
