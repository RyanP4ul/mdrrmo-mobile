import 'package:material_ui/material_ui.dart';

import '../../services/route_navigation.dart';
import '../../ui/kit.dart';
import 'responder_widgets.dart';

class ServiceScheduleCard extends StatelessWidget {
  const ServiceScheduleCard({
    super.key,
    required this.schedule,
    required this.onTap,
    this.showType = false,
  });

  final Map<String, dynamic> schedule;
  final VoidCallback onTap;
  final bool showType;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    final status = '${schedule['status'] ?? 'Unknown'}';
    final statusColor = switch (status.toLowerCase()) {
      'confirmed' => palette.success,
      'en-route' || 'on-scene' || 'completed' => palette.brand,
      'declined' || 'cancelled' => palette.danger,
      _ => palette.warning,
    };

    return ResponderPanel(
      padding: const EdgeInsets.all(AppSpacing.lg),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showType)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ResponderTag(
                  'SCHEDULED SERVICE',
                  icon: AppIcons.calendar,
                ),
              ),
            ),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 6,
            children: [
              Text(
                '${schedule['team_name'] ?? 'Response team'}',
                style: MdrrmoTypography.labelSm.copyWith(
                  color: palette.textMuted,
                ),
              ),
              ResponderTag(
                status,
                color: statusColor,
                icon: AppIcons.infoCircle,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${schedule['service_type'] ?? 'Service request'}',
            style: MdrrmoTypography.titleMd.copyWith(
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          _ServiceDetail(
            icon: AppIcons.pin,
            text: '${schedule['address'] ?? 'Destination not provided'}',
          ),
          const SizedBox(height: 6),
          _ServiceDetail(
            icon: AppIcons.calendar,
            text:
                '${schedule['preferred_date'] ?? 'Date not provided'} · ${schedule['preferred_time'] ?? 'Time not provided'}',
          ),
          const SizedBox(height: 6),
          _ServiceDetail(
            icon: AppIcons.user,
            text: '${schedule['resident'] ?? 'Resident not provided'}',
          ),
          if (schedule['contact'] != null &&
              '${schedule['contact']}'.isNotEmpty) ...[
            const SizedBox(height: 6),
            _ServiceDetail(
              icon: AppIcons.phone,
              text: '${schedule['contact']}',
            ),
          ],
          if (schedule['notes'] != null &&
              '${schedule['notes']}'.isNotEmpty) ...[
            const SizedBox(height: 6),
            _ServiceDetail(
              icon: AppIcons.form,
              text: '${schedule['notes']}',
            ),
          ],
          const SizedBox(height: 12),
          Divider(height: 1, color: palette.border),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: onTap,
                icon: const Icon(AppIcons.form, size: 17),
                label: const Text('Details and progress'),
              ),
              if (['confirmed', 'en-route', 'on-scene']
                  .contains(status.toLowerCase()))
                TextButton.icon(
                  style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: () => navigateToDestination(
                    context,
                    address: '${schedule['address'] ?? ''}',
                  ),
                  icon: const Icon(AppIcons.navigation, size: 17),
                  label: const Text('Navigate'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ServiceDetail extends StatelessWidget {
  const _ServiceDetail({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: palette.brand),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: MdrrmoTypography.bodySm.copyWith(
              color: palette.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
