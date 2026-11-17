import 'package:material_ui/material_ui.dart';

import '../ui/kit.dart';
import '../data/resident_models.dart';

// ───────────────────────── Status pills ─────────────────────────
Widget statusPill(IncidentStatus s, [BuildContext? context]) {
  final palette = context != null ? MdrrmoColors.of(context) : null;
  return switch (s) {
    IncidentStatus.unknown => AppStatusBadge(
      'Status unavailable',
      color: palette?.textMuted ?? AppColors.neutral,
      icon: AppIcons.infoCircle,
    ),
    IncidentStatus.active => AppStatusBadge(
      'Waiting for review',
      color: palette?.warning ?? Semantic.warning,
      icon: AppIcons.clock,
    ),
    IncidentStatus.responding => AppStatusBadge(
      'Help on the way',
      color: palette?.brand ?? AppColors.primary,
      icon: AppIcons.truck,
    ),
    IncidentStatus.resolved => AppStatusBadge(
      'Completed',
      color: palette?.success ?? Semantic.success,
      icon: AppIcons.checkCircle,
    ),
    IncidentStatus.withdrawn => AppStatusBadge(
      'Cancelled',
      color: palette?.textMuted ?? AppColors.neutral,
      icon: AppIcons.close,
    ),
    IncidentStatus.invalid => AppStatusBadge(
      'Closed',
      color: palette?.danger ?? Semantic.danger,
      icon: AppIcons.infoCircle,
    ),
  };
}

/// Plain-language status label & badge for resident service/report records.
(String, Color, IconData) residentStatusPresentation(
  String rawStatus,
  MdrrmoColors palette, {
  bool schedule = false,
}) {
  final normalized = rawStatus.toLowerCase().trim();
  if (schedule) {
    return switch (normalized) {
      'pending' => ('Waiting for confirmation', palette.warning, AppIcons.clock),
      'acknowledged' => ('Under review', palette.brand, AppIcons.infoCircle),
      'confirmed' => ('Confirmed', palette.success, AppIcons.checkCircle),
      'en-route' => ('Team on the way', palette.brand, AppIcons.truck),
      'on-scene' => ('Team on site', palette.brand, AppIcons.pin),
      'completed' => ('Completed', palette.success, AppIcons.checkCircle),
      'cancelled' => ('Cancelled', palette.textMuted, AppIcons.close),
      'declined' => ('Declined', palette.danger, AppIcons.infoCircle),
      _ => ('In progress', palette.textMuted, AppIcons.infoCircle),
    };
  }
  return switch (normalized) {
    'pending' => ('Waiting for review', palette.warning, AppIcons.clock),
    'acknowledged' => ('Received by MDRRMO', palette.brand, AppIcons.infoCircle),
    'dispatched' => ('Help on the way', palette.brand, AppIcons.truck),
    'resolved' => ('Completed', palette.success, AppIcons.checkCircle),
    'withdrawn' => ('Cancelled', palette.textMuted, AppIcons.close),
    'invalid' => ('Closed', palette.danger, AppIcons.infoCircle),
    _ => ('Status unavailable', palette.textMuted, AppIcons.infoCircle),
  };
}

Widget residentStatusBadge(
  String rawStatus,
  BuildContext context, {
  bool schedule = false,
}) {
  final palette = MdrrmoColors.of(context);
  final (label, color, icon) = residentStatusPresentation(
    rawStatus,
    palette,
    schedule: schedule,
  );
  return AppStatusBadge(label, color: color, icon: icon);
}

/// Rounded icon tile in the category colour (solid) or tinted (soft).
class IncidentTile extends StatelessWidget {
  const IncidentTile(this.type, {super.key, this.size = 46, this.soft = false});
  final IncidentType type;
  final double size;
  final bool soft;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    final bg = soft
        ? type.color.withValues(alpha: palette.isDark ? 0.22 : 0.12)
        : type.color;
    final fg = soft
        ? (type.color == IncidentType.disaster.color
            ? palette.warningIcon
            : type.color)
        : type.onColor;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: soft
            ? Border.all(
                color: type.color.withValues(alpha: palette.isDark ? 0.38 : 0.26),
              )
            : null,
      ),
      child: Icon(type.icon, size: size * .48, color: fg),
    );
  }
}

// ───────────────────────── Form helpers ─────────────────────────
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text, {this.locked = false});
  final String text;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Flexible(
            child: Text(
              text,
              style: MdrrmoTypography.bodySm.copyWith(
                fontWeight: FontWeight.w600,
                color: palette.textPrimary,
              ),
            ),
          ),
          if (locked) ...[
            const SizedBox(width: 6),
            Icon(AppIcons.lock, size: 12, color: palette.textMuted),
          ],
        ],
      ),
    );
  }
}

/// Tappable `48dp` field that opens a date/time picker.
class PickerField extends StatelessWidget {
  const PickerField({
    super.key,
    required this.label,
    required this.icon,
    required this.placeholder,
    required this.value,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final String placeholder;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label),
        Semantics(
          button: true,
          label: '$label, ${value ?? placeholder}',
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color: value == null
                      ? palette.border
                      : palette.brand.withValues(alpha: 0.45),
                ),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: palette.brand),
                  const SizedBox(width: AppSpacing.sm + 2),
                  Expanded(
                    child: Text(
                      value ?? placeholder,
                      style: MdrrmoTypography.tabular(
                        MdrrmoTypography.bodyMd.copyWith(
                          color: value == null
                              ? palette.textMuted
                              : palette.textPrimary,
                          fontWeight: value == null
                              ? FontWeight.w400
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  Icon(
                    AppIcons.chevron,
                    size: 16,
                    color: palette.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Read-only field for account-derived values.
class LockedField extends StatelessWidget {
  const LockedField({
    super.key,
    required this.label,
    required this.icon,
    required this.value,
  });
  final String label;
  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label, locked: true),
        Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: palette.surfaceSubtle,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: palette.textMuted),
              const SizedBox(width: AppSpacing.sm + 2),
              Expanded(
                child: Text(
                  value,
                  style: MdrrmoTypography.bodyMd.copyWith(
                    color: palette.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
