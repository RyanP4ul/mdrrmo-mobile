import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';
import '../../ui/kit.dart';
import '../record_details_screen.dart';

class DispatchDetailsScreen extends StatelessWidget {
  const DispatchDetailsScreen({super.key, required this.dispatch});
  final Dispatch dispatch;

  @override
  Widget build(BuildContext context) => dispatch.recordId == null
      ? AppScaffold(
          header: pushedHeader(context, 'Dispatch details'),
          child: const Center(
            child: ContentFrame(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: AppStateView(
                  icon: AppIcons.infoCircle,
                  title: 'Legacy dispatch record',
                  message:
                      'This legacy record has no server ID. Refresh history.',
                ),
              ),
            ),
          ),
        )
      : RecordDetailsScreen(id: dispatch.recordId!, driver: true);
}
