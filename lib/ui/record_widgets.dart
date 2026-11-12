import 'package:material_ui/material_ui.dart';

import 'kit.dart';

String readableLabel(Object? value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return 'Not recorded';
  return text
      .replaceAllMapped(
        RegExp(r'([a-z])([A-Z])'),
        (match) => '${match[1]} ${match[2]}',
      )
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .split(' ')
      .where((word) => word.isNotEmpty)
      .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');
}

String recordTimestamp(Object? value, {bool dateOnly = false}) {
  if (value == null || '$value'.trim().isEmpty) return 'Not recorded';
  final date = DateTime.tryParse('$value');
  if (date == null) return '$value';
  final local = dateOnly ? date : date.toLocal();
  return dateOnly ? fmtDate(local) : '${fmtDate(local)} · ${fmtTime(local)}';
}

String recordTime(Object? value) {
  if (value == null || '$value'.trim().isEmpty) return 'Not recorded';
  final match = RegExp(r'^(\d{1,2}):(\d{2})(?::\d{2})?$').firstMatch('$value');
  if (match == null) return '$value';
  final hour = int.parse(match[1]!), minute = int.parse(match[2]!);
  if (hour > 23 || minute > 59) return '$value';
  return '${hour % 12 == 0 ? 12 : hour % 12}:${minute.toString().padLeft(2, '0')} ${hour < 12 ? 'AM' : 'PM'}';
}

Color recordStatusColor(String status, [BuildContext? context]) {
  final palette = context != null ? MdrrmoColors.of(context) : null;
  return switch (status.toLowerCase()) {
    'resolved' || 'completed' || 'available' || 'approved' =>
      palette?.success ?? Semantic.success,
    'declined' || 'cancelled' || 'critical' || 'high' =>
      palette?.danger ?? Semantic.danger,
    'pending' || 'medium' => palette?.warning ?? Semantic.warning,
    'acknowledged' ||
    'confirmed' ||
    'dispatched' ||
    'en-route' ||
    'on-scene' => palette?.brand ?? AppColors.primary,
    _ => palette?.textMuted ?? AppColors.neutral,
  };
}

class RecordBadge extends StatelessWidget {
  const RecordBadge(this.value, {super.key, this.color, this.icon});
  final String value;
  final Color? color;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final accent = color ?? recordStatusColor(value, context);
    return AppStatusBadge(
      readableLabel(value),
      color: accent,
      icon: icon,
    );
  }
}

class DetailSection extends StatelessWidget {
  const DetailSection({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
    this.color = AppColors.primary,
  });
  final String title;
  final IconData icon;
  final List<Widget> children;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Surface(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
                const SizedBox(width: AppSpacing.sm + 2),
                Expanded(
                  child: Text(
                    title,
                    style: MdrrmoTypography.titleMd.copyWith(
                      color: palette.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md + 2),
            ...children,
          ],
        ),
      ),
    );
  }
}

class DetailField extends StatelessWidget {
  const DetailField(
    this.label,
    this.value, {
    super.key,
    this.icon,
    this.fallback = 'Not recorded',
  });
  final String label;
  final Object? value;
  final IconData? icon;
  final String fallback;
  @override
  Widget build(BuildContext context) {
    final text = value?.toString().trim();
    final missing = text == null || text.isEmpty;
    final palette = MdrrmoColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 16, color: palette.textMuted),
            ),
            const SizedBox(width: AppSpacing.sm + 2),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: MdrrmoTypography.labelSm.copyWith(
                    color: palette.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                SelectableText(
                  missing ? fallback : text,
                  style: MdrrmoTypography.bodyMd.copyWith(
                    color: missing ? palette.textMuted : palette.textPrimary,
                    fontWeight: missing ? FontWeight.w400 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class RecordOverview extends StatelessWidget {
  const RecordOverview({
    super.key,
    required this.reference,
    required this.title,
    required this.status,
    required this.icon,
    this.priority,
    this.subtitle,
    this.color = AppColors.primary,
  });
  final String reference, title, status;
  final IconData icon;
  final String? priority, subtitle;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md + 2),
      child: Surface(
        tint: Color.alphaBlend(
          color.withValues(alpha: palette.isDark ? 0.08 : 0.04),
          palette.surface,
        ),
        borderColor: color.withValues(alpha: palette.isDark ? 0.36 : 0.28),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        reference,
                        style: MdrrmoTypography.tabular(
                          MdrrmoTypography.labelSm.copyWith(
                            color: palette.textMuted,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        style: MdrrmoTypography.displaySm.copyWith(
                          fontSize: 20,
                          color: palette.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md + 2),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                RecordBadge(status),
                if (priority != null)
                  RecordBadge(
                    '$priority priority',
                    color: recordStatusColor(priority!, context),
                    icon: AppIcons.flag,
                  ),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: AppSpacing.sm + 2),
              Text(
                subtitle!,
                style: MdrrmoTypography.bodySm.copyWith(
                  color: palette.textSecondary,
                  height: 1.45,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class RecordMessage extends StatelessWidget {
  const RecordMessage({
    super.key,
    required this.title,
    required this.message,
    this.icon = AppIcons.info,
    this.onRetry,
  });
  final String title, message;
  final IconData icon;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => DetailSection(
    title: title,
    icon: icon,
    children: [
      Text(
        message,
        style: MdrrmoTypography.bodyMd.copyWith(
          color: MdrrmoColors.of(context).textSecondary,
        ),
      ),
      if (onRetry != null) ...[
        const SizedBox(height: AppSpacing.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: AppButton(
            label: 'Try again',
            icon: AppIcons.refresh,
            kind: AppButtonKind.outline,
            onPress: onRetry,
          ),
        ),
      ],
    ],
  );
}
