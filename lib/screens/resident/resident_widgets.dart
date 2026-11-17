import 'package:material_ui/material_ui.dart';

import '../../data/resident_models.dart';
import '../../ui/kit.dart';
import '../../widgets/res_widgets.dart';

const residentPrimary = AppColors.primary;

class ResidentPanel extends StatelessWidget {
  const ResidentPanel({
    super.key,
    required this.child,
    this.onTap,
    this.tint,
    this.borderColor,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
  });
  final Widget child;
  final VoidCallback? onTap;
  final Color? tint;
  final Color? borderColor;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Surface(
    padding: padding,
    onTap: onTap,
    tint: tint,
    borderColor: borderColor,
    radius: AppRadius.md,
    child: child,
  );
}

class ResidentHeading extends StatelessWidget {
  const ResidentHeading(this.title, {super.key, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => AppHeading(
    title,
    subtitle: subtitle,
    trailing: trailing,
    bottomSpacing: AppSpacing.md + 2,
  );
}

class ResidentEmptyState extends StatelessWidget {
  const ResidentEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title, message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => AppStateView(
    icon: icon,
    title: title,
    message: message,
    accent: MdrrmoColors.of(context).brand,
    action: action,
  );
}

class ResidentShortcut extends StatelessWidget {
  const ResidentShortcut({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title, subtitle;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    final enabled = onTap != null;
    return ColoredBox(
      color: enabled ? palette.surface : palette.surfaceSubtle,
      child: AppRowItem(
        title: title,
        subtitle: subtitle,
        enabled: enabled,
        onTap: onTap,
        showChevron: true,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        leading: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: palette.brand.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Icon(
            icon,
            color: enabled ? palette.brand : palette.textMuted,
            size: 20,
          ),
        ),
      ),
    );
  }
}

class ResidentReportCard extends StatelessWidget {
  const ResidentReportCard({
    super.key,
    required this.report,
    required this.onTap,
  });
  final ReportRecord report;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            IncidentTile(report.type, soft: true, size: 40),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          report.type.label,
                          style: MdrrmoTypography.titleMd.copyWith(
                            fontSize: 15,
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        report.reference,
                        style: MdrrmoTypography.tabular(
                          MdrrmoTypography.labelSm.copyWith(
                            color: palette.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    report.location,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: MdrrmoTypography.bodySm.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      statusPill(report.status, context),
                      Text(
                        '${fmtDay(report.time)} · ${fmtTime(report.time)}',
                        style: MdrrmoTypography.tabular(
                          MdrrmoTypography.labelSm.copyWith(
                            color: palette.textMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(
              AppIcons.chevron,
              size: 18,
              color: palette.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class ResidentFormStep extends StatelessWidget {
  const ResidentFormStep({super.key, required this.step, required this.label});
  final int step;
  final String label;
  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'STEP $step OF 2 · $label',
            style: MdrrmoTypography.labelSm.copyWith(
              letterSpacing: 0.6,
              fontWeight: FontWeight.w700,
              color: palette.brand,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              for (final index in [1, 2])
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: index == 1 ? 6 : 0),
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: index <= step
                            ? palette.brand
                            : palette.border,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
