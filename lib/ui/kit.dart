// All Forui & shared UI component usage is centralized through lib/ui/kit.dart
// so theming, accessibility, and toolkit boundaries stay consistent across screens.
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import '../data/models.dart';
import '../data/input_validation.dart';
import 'app_theme.dart';
import 'components.dart';
export '../data/api_errors.dart';
export 'app_theme.dart';
export 'components.dart';

// ───────────────────────────── Icons ─────────────────────────────
/// Unified Lucide icon registry (`forui_lucide`) — eliminates raw `Icons.*` drift.
class AppIcons {
  static const home = FLucideIcons.house;
  static const history = FLucideIcons.history;
  static const bell = FLucideIcons.bell;
  static const bellDot = FLucideIcons.bellDot;
  static const logout = FLucideIcons.logOut;
  static const pin = FLucideIcons.mapPin;
  static const navigation = FLucideIcons.navigation;
  static const users = FLucideIcons.users;
  static const alert = FLucideIcons.triangleAlert;
  static const form = FLucideIcons.fileText;
  static const fileCheck = FLucideIcons.fileCheck2;
  static const clock = FLucideIcons.clock;
  static const check = FLucideIcons.check;
  static const car = FLucideIcons.car;
  static const truck = FLucideIcons.truck;
  static const ambulance = FLucideIcons.ambulance;
  static const user = FLucideIcons.user;
  static const phone = FLucideIcons.phone;
  static const phoneCall = FLucideIcons.phoneCall;
  static const phoneOff = FLucideIcons.phoneOff;
  static const mic = FLucideIcons.mic;
  static const micOff = FLucideIcons.micOff;
  static const volumeOn = FLucideIcons.volume2;
  static const volumeOff = FLucideIcons.volumeX;
  static const chevron = FLucideIcons.chevronRight;
  static const chevronDown = FLucideIcons.chevronDown;
  static const chevronUp = FLucideIcons.chevronUp;
  static const back = FLucideIcons.arrowLeft;
  static const calendar = FLucideIcons.calendar;
  static const route = FLucideIcons.route;
  static const siren = FLucideIcons.siren;
  static const locate = FLucideIcons.locateFixed;
  static const fire = FLucideIcons.flame;
  static const medical = FLucideIcons.heartPulse;
  static const stethoscope = FLucideIcons.stethoscope;
  static const activity = FLucideIcons.activity;
  static const trauma = FLucideIcons.wind;
  static const rescue = FLucideIcons.lifeBuoy;
  static const safety = FLucideIcons.shieldCheck;
  static const shieldAlert = FLucideIcons.shieldAlert;
  static const relief = FLucideIcons.waves;
  static const drill = FLucideIcons.clipboardList;
  static const lock = FLucideIcons.lock;
  static const bolt = FLucideIcons.zap;
  static const star = FLucideIcons.star;
  static const checkCircle = FLucideIcons.circleCheck;
  static const infoCircle = FLucideIcons.circleAlert;
  static const info = FLucideIcons.info;
  static const send = FLucideIcons.send;
  static const house = FLucideIcons.house;
  static const search = FLucideIcons.search;
  static const refresh = FLucideIcons.refreshCw;
  static const wrench = FLucideIcons.wrench;
  static const map = FLucideIcons.map;
  static const filter = FLucideIcons.slidersHorizontal;
  static const hospital = FLucideIcons.hospital;
  static const building = FLucideIcons.building2;
  static const mail = FLucideIcons.mail;
  static const plus = FLucideIcons.plus;
  static const trash = FLucideIcons.trash2;
  static const close = FLucideIcons.x;
  static const wifi = FLucideIcons.wifi;
  static const wifiOff = FLucideIcons.wifiOff;
  static const inbox = FLucideIcons.inbox;
  static const edit = FLucideIcons.pencil;
  static const camera = FLucideIcons.camera;
  static const upload = FLucideIcons.upload;
  static const badgeCheck = FLucideIcons.badgeCheck;
  static const flag = FLucideIcons.flag;
  static const radio = FLucideIcons.radio;
  static const ban = FLucideIcons.ban;
  static const more = FLucideIcons.ellipsis;
  static const dot = FLucideIcons.circle;
  static const settings = FLucideIcons.settings;
}

// ─────────────────────────── Text tokens ─────────────────────────
class AppType {
  const AppType();
  final TextStyle xs = MdrrmoTypography.labelSm;
  final TextStyle sm = MdrrmoTypography.bodySm;
  final TextStyle base = MdrrmoTypography.bodyMd;
  final TextStyle lg = MdrrmoTypography.titleLg;
  final TextStyle xl = MdrrmoTypography.displaySm;
}

const appType = AppType();

// ─────────────────────── Semantic colours ────────────────────────
class Semantic {
  static const success = AppColors.success;
  static const warning = AppColors.warning;
  static const danger = AppColors.danger;
  static const info = AppColors.info;
  static const neutral = AppColors.neutral;

  static Color priority(Priority p) => switch (p) {
    Priority.low => success,
    Priority.medium => warning,
    Priority.high => danger,
    Priority.critical => danger,
  };
}

// ───────────────────────── Formatting ────────────────────────────
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String fmtTime(DateTime d) {
  d = d.toLocal();
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
}

String fmtDay(DateTime d) {
  d = d.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(DateTime(d.year, d.month, d.day)).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return '${_months[d.month - 1]} ${d.day}, ${d.year}';
}

String fmtDate(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

String timeAgo(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) {
    return '${diff.inMinutes} min${diff.inMinutes == 1 ? '' : 's'} ago';
  }
  if (diff.inHours < 24) {
    return '${diff.inHours} hr${diff.inHours == 1 ? '' : 's'} ago';
  }
  if (diff.inDays == 1) return 'Yesterday';
  return fmtDate(d);
}

String priorityLabel(Priority p) => switch (p) {
  Priority.low => 'Low',
  Priority.medium => 'Medium',
  Priority.high => 'High',
  Priority.critical => 'Critical',
};

// ───────────────────────── Buttons ───────────────────────────────
enum AppButtonKind { primary, secondary, outline, destructive, dangerOutline }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPress,
    this.icon,
    this.kind = AppButtonKind.primary,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPress;
  final IconData? icon;
  final AppButtonKind kind;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    final effectivePress = loading ? null : onPress;
    final foregroundOverride = kind == AppButtonKind.dangerOutline
        ? palette.danger
        : null;

    final Widget labelWidget = Text(
      label,
      textAlign: TextAlign.center,
      style: foregroundOverride == null
          ? null
          : TextStyle(color: foregroundOverride),
    );

    final child = loading
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator.adaptive(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    kind == AppButtonKind.primary ||
                            kind == AppButtonKind.destructive
                        ? palette.brandOn
                        : (foregroundOverride ?? palette.brand),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(child: labelWidget),
            ],
          )
        : icon == null
        ? labelWidget
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: foregroundOverride),
              const SizedBox(width: 8),
              Flexible(child: labelWidget),
            ],
          );

    final VoidCallback? onPressed = effectivePress == null
        ? null
        : () {
            HapticFeedback.selectionClick();
            effectivePress();
          };

    final Widget button = switch (kind) {
      AppButtonKind.primary => FilledButton(
        onPressed: onPressed,
        child: child,
      ),
      AppButtonKind.destructive => FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: palette.danger,
          foregroundColor: palette.brandOn,
          disabledBackgroundColor: palette.danger.withValues(alpha: 0.38),
          disabledForegroundColor: palette.brandOn.withValues(alpha: 0.72),
        ),
        child: child,
      ),
      AppButtonKind.secondary => FilledButton.tonal(
        onPressed: onPressed,
        child: child,
      ),
      AppButtonKind.outline => OutlinedButton(
        onPressed: onPressed,
        child: child,
      ),
      AppButtonKind.dangerOutline => OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.danger,
          side: BorderSide(color: palette.danger.withValues(alpha: 0.45)),
        ),
        child: child,
      ),
    };

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: button,
    );
  }
}

// ───────────────────────── Text field ────────────────────────────
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    this.keyboardType,
    this.maxLines = 1,
    this.maxLength = 255,
    this.required = true,
    this.validator,
    this.textInputAction = TextInputAction.next,
    this.autofillHints,
    this.readOnly = false,
    this.enabled = true,
    this.onTap,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputType? keyboardType;
  final int maxLines;
  final int maxLength;
  final bool required;
  final String? Function(String?)? validator;
  final Iterable<String>? autofillHints;
  final TextInputAction textInputAction;
  final bool readOnly;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return FTextFormField(
      control: FTextFieldControl.managed(controller: controller),
      label: Text(required ? label : '$label (optional)'),
      hint: hint,
      keyboardType: keyboardType,
      maxLines: maxLines,
      maxLength: maxLength,
      readOnly: readOnly,
      enabled: enabled,
      onTap: onTap,
      textInputAction: textInputAction,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (v) {
        final error = InputValidation.text(
          v,
          label,
          maxLength,
          required: required,
        );
        if (error != null) return error;
        return validator?.call(v);
      },
      autofillHints: autofillHints,
    );
  }
}

/// Password field using Forui's built-in show/hide toggle.
class AppPasswordField extends StatelessWidget {
  const AppPasswordField({
    super.key,
    required this.controller,
    this.label = 'Password',
    this.hint = 'Enter your password',
    this.onSubmit,
    this.extraValidator,
    this.textInputAction = TextInputAction.done,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final VoidCallback? onSubmit;
  final String? Function(String value)? extraValidator;
  final TextInputAction textInputAction;

  @override
  Widget build(BuildContext context) {
    return FTextFormField.password(
      control: FTextFieldControl.managed(controller: controller),
      label: Text(label),
      hint: hint,
      textInputAction: textInputAction,
      onSubmit: onSubmit == null ? null : (_) => onSubmit!(),
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (v) {
        if (v == null || v.isEmpty) return 'Password is required';
        if (v.runes.length > 128) return 'Use at most 128 characters';
        return extraValidator?.call(v);
      },
    );
  }
}

// ───────────────────────────── Select ────────────────────────────
class AppSelect extends StatelessWidget {
  const AppSelect({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChange,
  });

  final String label;
  final List<String> options;
  final String value;
  final ValueChanged<String> onChange;

  @override
  Widget build(BuildContext context) {
    return FSelect<String>(
      label: Text(label),
      hint: 'Select',
      items: {for (final o in options) o: o},
      control: FSelectControl<String>.managed(
        initial: value,
        onChange: (v) {
          if (v != null) onChange(v);
        },
      ),
    );
  }
}

// ───────────────────────────── Dialog ────────────────────────────

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final palette = MdrrmoColors.of(context);
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: palette.danger,
                  foregroundColor: palette.brandOn,
                )
              : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

void snack(BuildContext context, String message) {
  final toaster = context.findAncestorStateOfType<FToasterState>();
  if (toaster != null) {
    showFToast(context: context, title: Text(message));
    return;
  }
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger != null && Scaffold.maybeOf(context) != null) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }
}

// ─────────────────────── Small shared widgets ────────────────────
const logoAsset = 'assets/images/mdrrmo-logo.webp';

/// The MDRRMO seal (source file 64x64).
class LogoMark extends StatelessWidget {
  const LogoMark({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    logoAsset,
    width: size,
    height: size,
    filterQuality: FilterQuality.high,
    semanticLabel: 'MDRRMO logo',
  );
}

// ─────────────────────── Status & Badge Pill ────────────────────
class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, required this.color, this.icon});
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => AppStatusBadge(
    label,
    color: color,
    dot: icon == null,
    icon: icon,
  );
}

class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar(this.name, {super.key, this.size = 40, this.online});
  final String name;
  final double size;
  final bool? online;

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.first.isEmpty) return '?';
    final a = parts.first[0];
    final b = parts.length > 1 ? parts.last[0] : '';
    return (a + b).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.brand.withValues(alpha: 0.14),
              shape: BoxShape.circle,
              border: Border.all(color: palette.brand.withValues(alpha: 0.3)),
            ),
            child: Text(
              _initials,
              style: TextStyle(
                color: palette.brand,
                fontWeight: FontWeight.w800,
                fontSize: (size * .36).clamp(12, 24),
              ),
            ),
          ),
          if (online != null)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: size * .3,
                height: size * .3,
                decoration: BoxDecoration(
                  color: online! ? palette.success : palette.textMuted,
                  shape: BoxShape.circle,
                  border: Border.all(color: palette.surface, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(
    this.title, {
    super.key,
    required this.icon,
    this.trailing,
  });
  final String title;
  final IconData icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: palette.brand.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(icon, size: 15, color: palette.brand),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: MdrrmoTypography.titleMd.copyWith(
                color: palette.textPrimary,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Crisp, restrained bordered surface used across the application.
class Surface extends StatelessWidget {
  const Surface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.tint,
    this.borderColor,
    this.radius = AppRadius.md,
  });
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? tint;
  final Color? borderColor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    final r = BorderRadius.circular(radius);
    return Material(
      color: tint ?? palette.surface,
      borderRadius: r,
      child: InkWell(
        borderRadius: r,
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: r,
            border: Border.all(color: borderColor ?? palette.border),
          ),
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

class SegmentOption<T> {
  const SegmentOption(this.value, this.label, {this.icon, this.color});
  final T value;
  final String label;
  final IconData? icon;
  final Color? color;
}

/// Thumb-friendly segmented control (`>= 48dp` interactive height).
class Segmented<T> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });
  final List<SegmentOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.surfaceSubtle,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          for (final o in options)
            Expanded(
              child: Semantics(
                button: true,
                selected: o.value == value,
                label: o.label,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onChanged(o.value);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    constraints: const BoxConstraints(minHeight: 44),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: o.value == value
                          ? (o.color ?? palette.brand)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (o.icon != null) ...[
                          Icon(
                            o.icon,
                            size: 15,
                            color: o.value == value
                                ? Colors.white
                                : palette.textSecondary,
                          ),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(
                            o.label,
                            textAlign: TextAlign.center,
                            style: MdrrmoTypography.bodySm.copyWith(
                              fontWeight: FontWeight.w700,
                              color: o.value == value
                                  ? Colors.white
                                  : palette.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Pickup -> destination route rail.
class RouteTimeline extends StatelessWidget {
  const RouteTimeline({
    super.key,
    required this.pickup,
    required this.destination,
    this.pickupNote,
    this.destinationNote,
  });
  final String pickup;
  final String destination;
  final String? pickupNote;
  final String? destinationNote;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);

    Widget stop(String caption, String place, String? note, Color color) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              caption.toUpperCase(),
              style: MdrrmoTypography.labelSm.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
                letterSpacing: .6,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              place,
              style: MdrrmoTypography.bodyMd.copyWith(
                fontWeight: FontWeight.w700,
                color: palette.textPrimary,
              ),
            ),
            if (note != null)
              Text(
                note,
                style: MdrrmoTypography.bodySm.copyWith(
                  color: palette.textMuted,
                ),
              ),
          ],
        );

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              const SizedBox(height: 4),
              Icon(AppIcons.pin, size: 18, color: palette.brand),
              Expanded(
                child: Container(
                  width: 2,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  color: palette.border,
                ),
              ),
              Icon(
                AppIcons.navigation,
                size: 18,
                color: palette.warningIcon,
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                stop('Pickup', pickup, pickupNote, palette.brand),
                const SizedBox(height: 14),
                stop(
                  'Destination',
                  destination,
                  destinationNote,
                  palette.warning,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal progress bar for dispatches (`24dp` circles, `12sp` label floor).
class StepperBar extends StatelessWidget {
  const StepperBar({super.key, required this.labels, required this.current});
  final List<String> labels;
  final int current;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          Expanded(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 2,
                        color: i == 0
                            ? Colors.transparent
                            : (i <= current ? palette.brand : palette.border),
                      ),
                    ),
                    Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i <= current
                            ? palette.brand
                            : palette.surfaceSubtle,
                        border: i == current
                            ? Border.all(
                                color: palette.brand.withValues(alpha: .28),
                                width: 3,
                              )
                            : Border.all(
                                color: i < current
                                    ? palette.brand
                                    : palette.border,
                              ),
                      ),
                      child: i < current
                          ? Icon(
                              AppIcons.check,
                              size: 13,
                              color: palette.brandOn,
                            )
                          : Text(
                              '${i + 1}',
                              style: MdrrmoTypography.labelSm.copyWith(
                                color: i == current
                                    ? palette.brandOn
                                    : palette.textMuted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                    Expanded(
                      child: Container(
                        height: 2,
                        color: i == labels.length - 1
                            ? Colors.transparent
                            : (i < current ? palette.brand : palette.border),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  labels[i],
                  textAlign: TextAlign.center,
                  style: MdrrmoTypography.labelSm.copyWith(
                    color: i <= current
                        ? palette.textPrimary
                        : palette.textMuted,
                    fontWeight: i == current
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Neutral top bar for pushed screens with Lucide back action and 1px hairline border.
Widget pushedHeader(
  BuildContext context,
  String title, {
  Color? backgroundColor,
  List<Widget> actions = const [],
  bool showBack = true,
  VoidCallback? onBack,
}) {
  final palette = MdrrmoColors.of(context);
  final hasFTheme = context.findAncestorWidgetOfExactType<FTheme>() != null;
  final handleBack = onBack ?? () => Navigator.of(context).maybePop();

  if (backgroundColor != null && hasFTheme) {
    return Container(
      color: backgroundColor,
      child: FHeader.nested(
        style: const .delta(
          systemOverlayStyle: SystemUiOverlayStyle.light,
        ),
        title: Text(
          title,
          style: MdrrmoTypography.titleLg.copyWith(color: Colors.white),
        ),
        prefixes: showBack
            ? [
                FHeaderAction(
                  icon: const Icon(
                    AppIcons.back,
                    color: Colors.white,
                    semanticLabel: 'Back',
                  ),
                  onPress: handleBack,
                ),
              ]
            : const [],
        suffixes: actions,
      ),
    );
  }

  if (hasFTheme) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: FHeader.nested(
        style: .delta(
          systemOverlayStyle: palette.isDark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark,
        ),
        title: Text(
          title,
          style: MdrrmoTypography.titleLg.copyWith(color: palette.textPrimary),
        ),
        prefixes: showBack
            ? [
                FHeaderAction(
                  icon: Icon(
                    AppIcons.back,
                    color: palette.textPrimary,
                    semanticLabel: 'Back',
                  ),
                  onPress: handleBack,
                ),
              ]
            : const [],
        suffixes: actions,
      ),
    );
  }

  return Material(
    color: backgroundColor ?? palette.surface,
    child: SafeArea(
      bottom: false,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: palette.border)),
        ),
        padding: EdgeInsets.symmetric(horizontal: showBack ? 4 : 16),
        child: Row(
          children: [
            if (showBack) ...[
              IconButton(
                tooltip: 'Back',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: handleBack,
                icon: Icon(
                  AppIcons.back,
                  color: backgroundColor != null
                      ? Colors.white
                      : palette.textPrimary,
                ),
              ),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MdrrmoTypography.titleLg.copyWith(
                  color: backgroundColor != null
                      ? Colors.white
                      : palette.textPrimary,
                ),
              ),
            ),
            ...actions,
          ],
        ),
      ),
    ),
  );
}

/// Supplies Material ancestry and brightness-aware canvas for all screens.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.child,
    this.header,
    this.footer,
    this.childPad = true,
  });
  final Widget child;
  final Widget? header, footer;
  final bool childPad;
  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    final hasFTheme = context.findAncestorWidgetOfExactType<FTheme>() != null;
    if (!hasFTheme) {
      return Scaffold(
        backgroundColor: palette.canvas,
        bottomNavigationBar: footer,
        body: Column(
          children: [
            ?header,
            Expanded(
              child: Padding(
                padding: childPad
                    ? const EdgeInsets.symmetric(horizontal: AppSpacing.lg)
                    : EdgeInsets.zero,
                child: child,
              ),
            ),
          ],
        ),
      );
    }

    return Material(
      color: palette.canvas,
      child: FScaffold(
        header: header,
        footer: footer == null
            ? null
            : MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: footer!,
              ),
        childPad: childPad,
        child: ColoredBox(color: palette.canvas, child: child),
      ),
    );
  }
}
