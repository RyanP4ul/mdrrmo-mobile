import 'package:material_ui/material_ui.dart';

import '../ui/kit.dart';
import 'record_browser_screen.dart';
import 'record_details_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.driver = false});
  final bool driver;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final entries = (widget.driver
            ? const [
                (
                  label: 'Submitted reports',
                  path: '/driver-responder/authored-reports',
                ),
                (label: 'Dispatch history', path: '/driver-responder/history'),
                (
                  label: 'Notifications',
                  path: '/driver-responder/notifications',
                ),
              ]
            : const [
                (label: 'Reports', path: '/resident/reports'),
                (label: 'Schedules', path: '/resident/schedules'),
                (label: 'Notifications', path: '/resident/notifications'),
              ]);
    final current = entries[_tab];

    return AppScaffold(
      header: pushedHeader(context, 'Search records'),
      childPad: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              0,
            ),
            child: ContentFrame(
              child: Segmented<int>(
                value: _tab,
                onChanged: (value) => setState(() => _tab = value),
                options: [
                  for (var i = 0; i < entries.length; i++)
                    SegmentOption(i, entries[i].label),
                ],
              ),
            ),
          ),
          Expanded(
            child: RecordBrowserView(
              key: ValueKey(current.path),
              path: current.path,
              label: (r) =>
                  '${r['reference'] ?? r['title'] ?? r['service_type'] ?? '#${r['id']}'}',
              subtitle: (r) =>
                  '${r['location'] ?? r['address'] ?? r['message'] ?? ''}\n${r['status'] ?? ''} ${r['reported_at'] ?? r['preferred_date'] ?? r['created_at'] ?? ''}',
              onOpen: (context, r) async {
                int? id;
                bool schedule = false;
                if (current.label == 'Notifications') {
                  if (widget.driver) {
                    id = r['report_id'] as int?;
                  } else {
                    final kind = r['related_type']
                        ?.toString()
                        .split('\\')
                        .last;
                    if (!['EmergencyReport', 'ServiceSchedule'].contains(kind)) {
                      return;
                    }
                    id = r['related_id'] as int?;
                    schedule = kind == 'ServiceSchedule';
                  }
                } else {
                  id = r['id'] as int;
                  schedule = current.label == 'Schedules';
                }
                if (id != null) {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RecordDetailsScreen(
                        id: id!,
                        driver: widget.driver,
                        schedule: schedule,
                      ),
                    ),
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
