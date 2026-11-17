import 'package:material_ui/material_ui.dart';

import '../../services/route_navigation.dart';
import '../../ui/kit.dart';
import 'responder_widgets.dart';

class ServiceScheduleCard extends StatelessWidget {
  const ServiceScheduleCard({
    super.key,
    required this.schedule,
    required this.onTap,
    this.onUpdated,
    this.showType = false,
  });

  final Map<String, dynamic> schedule;
  final VoidCallback onTap;
  final Future<void> Function()? onUpdated;
  final bool showType;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    final rawStatus = '${schedule['status'] ?? 'Unknown'}'.trim();
    final normalized = rawStatus.toLowerCase();
    final statusLabel = rawStatus.isEmpty
        ? 'Unknown'
        : '${rawStatus[0].toUpperCase()}${rawStatus.substring(1)}';
    final pickup = '${schedule['pickup_address'] ?? schedule['address'] ?? ''}'
        .trim();
    final destination = extractScheduleDestination(schedule);
    final date = '${schedule['preferred_date'] ?? ''}'.trim();
    final time = '${schedule['preferred_time'] ?? ''}'.trim();
    final whenText = [
      if (date.isNotEmpty) date,
      if (time.isNotEmpty) time,
    ].join(' · ');
    final resident = '${schedule['resident'] ?? ''}'.trim();
    final contact = '${schedule['contact'] ?? ''}'.trim();
    final notes = '${schedule['notes'] ?? ''}'.trim();
    final canNavigate = const [
      'confirmed',
      'en-route',
      'on-scene',
    ].contains(normalized);

    final statusColor = switch (normalized) {
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
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              Text(
                '${schedule['service_type'] ?? 'Service request'}',
                style: MdrrmoTypography.titleMd.copyWith(
                  color: palette.textPrimary,
                ),
              ),
              ResponderTag(statusLabel, color: statusColor),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            pickup.isEmpty
                ? 'Pickup address not provided'
                : (destination.isNotEmpty ? 'Pickup: $pickup' : pickup),
            style: MdrrmoTypography.bodyMd.copyWith(
              fontWeight: FontWeight.w500,
              color: palette.textPrimary,
            ),
          ),
          if (destination.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'Destination: $destination',
              style: MdrrmoTypography.bodySm.copyWith(
                color: palette.textSecondary,
              ),
            ),
          ],
          if (whenText.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              whenText,
              style: MdrrmoTypography.tabular(
                MdrrmoTypography.bodySm.copyWith(
                  color: palette.textSecondary,
                ),
              ),
            ),
          ],
          if (resident.isNotEmpty || contact.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (resident.isNotEmpty)
                  Text(
                    resident,
                    style: MdrrmoTypography.bodySm.copyWith(
                      fontWeight: FontWeight.w500,
                      color: palette.textPrimary,
                    ),
                  ),
                if (contact.isNotEmpty)
                  Text(
                    contact,
                    style: MdrrmoTypography.tabular(
                      MdrrmoTypography.bodySm.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (notes.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: palette.surfaceSubtle,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                notes,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: MdrrmoTypography.bodySm.copyWith(
                  color: palette.textSecondary,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Divider(height: 1, color: palette.border),
          const SizedBox(height: AppSpacing.sm + 2),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (canNavigate)
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                  ),
                  onPressed: () => navigateToDestination(
                    context,
                    address: normalized == 'on-scene' && destination.isNotEmpty
                        ? destination
                        : pickup,
                    schedule: scheduleNavFromRecord(
                      schedule,
                      onStatusUpdated: onUpdated,
                    ),
                  ),
                  child: Text(
                    normalized == 'on-scene'
                        ? 'Navigate to destination'
                        : 'Navigate to pickup',
                  ),
                ),
              TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                ),
                onPressed: onTap,
                child: const Text('Details and progress'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
