import 'package:material_ui/material_ui.dart';

import '../../data/api/driver_service.api.dart';
import '../../ui/kit.dart';
import '../../ui/page_loader.dart';
import '../record_details_screen.dart';
import 'responder_widgets.dart';
import 'service_schedule_card.dart';

class HomeAssignmentsSection extends StatefulWidget {
  const HomeAssignmentsSection({
    super.key,
    required this.api,
    this.activeAssignments = const [],
    this.assignmentsLoaded = true,
    this.assignmentsError,
    this.onRefreshAssignments,
  });

  final DriverApi api;
  final List<Widget> activeAssignments;
  final bool assignmentsLoaded;
  final Object? assignmentsError;
  final Future<void> Function()? onRefreshAssignments;

  @override
  State<HomeAssignmentsSection> createState() => _HomeAssignmentsSectionState();
}

class _HomeAssignmentsSectionState extends State<HomeAssignmentsSection> {
  List<Map<String, dynamic>> _services = [];
  int? _next;
  bool _loading = false;
  Object? _error;
  bool _moreError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (_loading || (more && _next == null)) return;
    setState(() {
      _loading = true;
      _error = null;
      _moreError = false;
    });
    try {
      final page = await widget.api.fetchServiceSchedulesPage(
        active: true,
        before: more ? _next : null,
      );
      if (!mounted) return;
      setState(() {
        _services = more
            ? [
                ..._services,
                ...page.items.where(
                  (item) => !_services.any((old) => old['id'] == item['id']),
                ),
              ]
            : page.items;
        _services.sort(
          (a, b) => '${a['preferred_date']} ${a['preferred_time']}'.compareTo(
            '${b['preferred_date']} ${b['preferred_time']}',
          ),
        );
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ResponderHeading('Assignments'),
        Column(
          key: const ValueKey('home-assignments-container'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_loading && _services.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Center(
                  child: CircularProgressIndicator(color: palette.brand),
                ),
              ),
            if (widget.activeAssignments.isEmpty &&
                widget.assignmentsLoaded &&
                widget.assignmentsError == null &&
                _services.isEmpty &&
                !_loading &&
                _error == null)
              Surface(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.xl,
                ),
                child: Column(
                  children: [
                    Text(
                      'No assignments yet',
                      textAlign: TextAlign.center,
                      style: MdrrmoTypography.titleMd.copyWith(
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Dispatches and confirmed services appear here.',
                      textAlign: TextAlign.center,
                      style: MdrrmoTypography.bodySm.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            for (final assignment in widget.activeAssignments)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: assignment,
              ),
            for (final service in _services)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ServiceScheduleCard(
                  schedule: service,
                  showType: true,
                  onUpdated: _load,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RecordDetailsScreen(
                        id: service['id'] as int,
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
      ],
    );
  }
}
