import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';

/// Centralized Royal Blue (#4169E1) brand & public safety color constants.
///
/// Prefer [MdrrmoColors.of] for runtime UI so surfaces, borders, and semantic
/// tints automatically adapt between light and dark themes.
class AppColors {
  const AppColors._();

  // Primary Brand — Royal Blue
  static const primary = Color(0xFF4169E1);
  static const primaryStrong = Color(0xFF3154B6);
  static const primaryLight = Color(0xFF5B82F6);
  static const onPrimary = Color(0xFFFFFFFF);
  static const primaryContainerLight = Color(0xFFEEF2FF);
  static const onPrimaryContainerLight = Color(0xFF1E3A8A);
  static const primaryContainerDark = Color(0xFF172554);
  static const onPrimaryContainerDark = Color(0xFFDBEAFE);

  // Legacy role header constant kept only until callers migrate cleanly.
  static const headerBlue = Color(0xFF1E40AF);

  // Neutral Surfaces — Light
  static const backgroundLight = Color(0xFFF8FAFC);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const mutedLight = Color(0xFFF1F5F9);
  static const foregroundLight = Color(0xFF0F172A);
  static const secondaryForegroundLight = Color(0xFF475569);
  static const mutedForegroundLight = Color(0xFF64748B);
  static const borderLight = Color(0xFFE2E8F0);
  static const borderStrongLight = Color(0xFFCBD5E1);

  // Neutral Surfaces — Dark
  static const backgroundDark = Color(0xFF0B1120);
  static const surfaceDark = Color(0xFF111827);
  static const mutedDark = Color(0xFF1E293B);
  static const foregroundDark = Color(0xFFF8FAFC);
  static const secondaryForegroundDark = Color(0xFFCBD5E1);
  static const mutedForegroundDark = Color(0xFF94A3B8);
  static const borderDark = Color(0xFF263244);
  static const borderStrongDark = Color(0xFF334155);

  // Semantic Public Safety States
  static const danger = Color(0xFFDC2626);
  static const dangerDark = Color(0xFFEF4444);
  static const dangerSoftLight = Color(0xFFFEF2F2);
  static const dangerSoftDark = Color(0xFF450A0A);
  static const dangerSurface = Color(0xFFFEF2F2);

  // Darkened amber text (#B45309) meets WCAG AA >=4.5:1 on light surfaces.
  static const warning = Color(0xFFB45309);
  static const warningIcon = Color(0xFFD97706);
  static const warningDark = Color(0xFFF59E0B);
  static const warningSoftLight = Color(0xFFFFFBEB);
  static const warningSoftDark = Color(0xFF451A03);
  static const warningSurface = Color(0xFFFFFBEB);

  static const success = Color(0xFF15803D);
  static const successDark = Color(0xFF22C55E);
  static const successSoftLight = Color(0xFFF0FDF4);
  static const successSoftDark = Color(0xFF052E16);
  static const successSurface = Color(0xFFF0FDF4);

  static const info = Color(0xFF4169E1);
  static const neutral = Color(0xFF64748B);
  static const primarySurface = Color(0xFFEEF2FF);
  static const primaryBorder = Color(0xFFC7D2FE);
}

/// Standardized 4px / 8px spacing scale.
class AppSpacing {
  const AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
}

/// Restrained border radius tokens (avoids oversized rounded AI cards).
class AppRadius {
  const AppRadius._();

  static const double xs = 6;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double pill = 999;
}

/// Brightness-aware palette exposed via [ThemeExtension] with safe fallback.
@immutable
class MdrrmoColors extends ThemeExtension<MdrrmoColors> {
  const MdrrmoColors({
    required this.isDark,
    required this.canvas,
    required this.surface,
    required this.surfaceSubtle,
    required this.border,
    required this.borderStrong,
    required this.brand,
    required this.brandPressed,
    required this.brandTint,
    required this.brandOn,
    required this.danger,
    required this.dangerTint,
    required this.warning,
    required this.warningIcon,
    required this.warningTint,
    required this.success,
    required this.successTint,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
  });

  final bool isDark;
  final Color canvas;
  final Color surface;
  final Color surfaceSubtle;
  final Color border;
  final Color borderStrong;
  final Color brand;
  final Color brandPressed;
  final Color brandTint;
  final Color brandOn;
  final Color danger;
  final Color dangerTint;
  final Color warning;
  final Color warningIcon;
  final Color warningTint;
  final Color success;
  final Color successTint;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  static const light = MdrrmoColors(
    isDark: false,
    canvas: AppColors.backgroundLight,
    surface: AppColors.surfaceLight,
    surfaceSubtle: AppColors.mutedLight,
    border: AppColors.borderLight,
    borderStrong: AppColors.borderStrongLight,
    brand: AppColors.primary,
    brandPressed: AppColors.primaryStrong,
    brandTint: AppColors.primaryContainerLight,
    brandOn: AppColors.onPrimary,
    danger: AppColors.danger,
    dangerTint: AppColors.dangerSoftLight,
    warning: AppColors.warning,
    warningIcon: AppColors.warningIcon,
    warningTint: AppColors.warningSoftLight,
    success: AppColors.success,
    successTint: AppColors.successSoftLight,
    textPrimary: AppColors.foregroundLight,
    textSecondary: AppColors.secondaryForegroundLight,
    textMuted: AppColors.mutedForegroundLight,
  );

  static const dark = MdrrmoColors(
    isDark: true,
    canvas: AppColors.backgroundDark,
    surface: AppColors.surfaceDark,
    surfaceSubtle: AppColors.mutedDark,
    border: AppColors.borderDark,
    borderStrong: AppColors.borderStrongDark,
    brand: AppColors.primaryLight,
    brandPressed: AppColors.primary,
    brandTint: AppColors.primaryContainerDark,
    brandOn: AppColors.onPrimary,
    danger: AppColors.dangerDark,
    dangerTint: AppColors.dangerSoftDark,
    warning: AppColors.warningDark,
    warningIcon: AppColors.warningDark,
    warningTint: AppColors.warningSoftDark,
    success: AppColors.successDark,
    successTint: AppColors.successSoftDark,
    textPrimary: AppColors.foregroundDark,
    textSecondary: AppColors.secondaryForegroundDark,
    textMuted: AppColors.mutedForegroundDark,
  );

  static MdrrmoColors of(BuildContext context) {
    final ext = Theme.of(context).extension<MdrrmoColors>();
    if (ext != null) return ext;
    return Theme.brightnessOf(context) == Brightness.dark ? dark : light;
  }

  @override
  MdrrmoColors copyWith({
    bool? isDark,
    Color? canvas,
    Color? surface,
    Color? surfaceSubtle,
    Color? border,
    Color? borderStrong,
    Color? brand,
    Color? brandPressed,
    Color? brandTint,
    Color? brandOn,
    Color? danger,
    Color? dangerTint,
    Color? warning,
    Color? warningIcon,
    Color? warningTint,
    Color? success,
    Color? successTint,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
  }) => MdrrmoColors(
    isDark: isDark ?? this.isDark,
    canvas: canvas ?? this.canvas,
    surface: surface ?? this.surface,
    surfaceSubtle: surfaceSubtle ?? this.surfaceSubtle,
    border: border ?? this.border,
    borderStrong: borderStrong ?? this.borderStrong,
    brand: brand ?? this.brand,
    brandPressed: brandPressed ?? this.brandPressed,
    brandTint: brandTint ?? this.brandTint,
    brandOn: brandOn ?? this.brandOn,
    danger: danger ?? this.danger,
    dangerTint: dangerTint ?? this.dangerTint,
    warning: warning ?? this.warning,
    warningIcon: warningIcon ?? this.warningIcon,
    warningTint: warningTint ?? this.warningTint,
    success: success ?? this.success,
    successTint: successTint ?? this.successTint,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    textMuted: textMuted ?? this.textMuted,
  );

  @override
  MdrrmoColors lerp(covariant ThemeExtension<MdrrmoColors>? other, double t) {
    if (other is! MdrrmoColors) return this;
    return MdrrmoColors(
      isDark: t < 0.5 ? isDark : other.isDark,
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceSubtle: Color.lerp(surfaceSubtle, other.surfaceSubtle, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      brand: Color.lerp(brand, other.brand, t)!,
      brandPressed: Color.lerp(brandPressed, other.brandPressed, t)!,
      brandTint: Color.lerp(brandTint, other.brandTint, t)!,
      brandOn: Color.lerp(brandOn, other.brandOn, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerTint: Color.lerp(dangerTint, other.dangerTint, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningIcon: Color.lerp(warningIcon, other.warningIcon, t)!,
      warningTint: Color.lerp(warningTint, other.warningTint, t)!,
      success: Color.lerp(success, other.success, t)!,
      successTint: Color.lerp(successTint, other.successTint, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
    );
  }
}

/// Disciplined 6-tier typography scale (`12sp` hard floor for functional text).
class MdrrmoTypography {
  const MdrrmoTypography._();

  static const displaySm = TextStyle(
    fontSize: 22,
    height: 28 / 22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
  );

  static const titleLg = TextStyle(
    fontSize: 18,
    height: 24 / 18,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
  );

  static const titleMd = TextStyle(
    fontSize: 16,
    height: 22 / 16,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
  );

  static const bodyMd = TextStyle(
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w400,
  );

  static const bodySm = TextStyle(
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w400,
  );

  static const labelSm = TextStyle(
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
  );

  static TextStyle tabular(TextStyle base) => base.copyWith(
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

class AppTheme {
  const AppTheme._();

  static final light = _royalBlueLight(FTheme.neutral.light.touch);
  static final dark = _royalBlueDark(FTheme.neutral.dark.touch);

  static final ThemeData materialLight = buildMaterialTheme(
    light,
    brightness: Brightness.light,
  );
  static final ThemeData materialDark = buildMaterialTheme(
    dark,
    brightness: Brightness.dark,
  );

  static FThemeData _royalBlueLight(FThemeData base) => FThemeData(
    touch: true,
    colors: base.colors.copyWith(
      primary: AppColors.primary,
      primaryForeground: AppColors.onPrimary,
      secondary: AppColors.mutedLight,
      secondaryForeground: AppColors.foregroundLight,
      background: AppColors.surfaceLight,
      foreground: AppColors.foregroundLight,
      muted: AppColors.mutedLight,
      mutedForeground: AppColors.mutedForegroundLight,
      border: AppColors.borderLight,
      destructive: AppColors.danger,
      destructiveForeground: AppColors.onPrimary,
      error: AppColors.danger,
      errorForeground: AppColors.onPrimary,
    ),
  );

  static FThemeData _royalBlueDark(FThemeData base) => FThemeData(
    touch: true,
    colors: base.colors.copyWith(
      primary: AppColors.primaryLight,
      primaryForeground: AppColors.onPrimary,
      secondary: AppColors.mutedDark,
      secondaryForeground: AppColors.foregroundDark,
      background: AppColors.surfaceDark,
      foreground: AppColors.foregroundDark,
      muted: AppColors.mutedDark,
      mutedForeground: AppColors.mutedForegroundDark,
      border: AppColors.borderDark,
      destructive: AppColors.dangerDark,
      destructiveForeground: AppColors.onPrimary,
      error: AppColors.dangerDark,
      errorForeground: AppColors.onPrimary,
    ),
  );

  static ThemeData buildMaterialTheme(
    FThemeData fTheme, {
    required Brightness brightness,
  }) {
    final palette = brightness == Brightness.dark
        ? MdrrmoColors.dark
        : MdrrmoColors.light;

    final base = fTheme.toApproximateMaterialTheme();
    final scheme = base.colorScheme.copyWith(
      brightness: brightness,
      primary: palette.brand,
      onPrimary: palette.brandOn,
      primaryContainer: palette.brandTint,
      onPrimaryContainer: palette.isDark
          ? AppColors.onPrimaryContainerDark
          : AppColors.onPrimaryContainerLight,
      secondary: palette.brandPressed,
      onSecondary: palette.brandOn,
      secondaryContainer: palette.brandTint,
      onSecondaryContainer: palette.isDark
          ? AppColors.onPrimaryContainerDark
          : AppColors.onPrimaryContainerLight,
      surface: palette.surface,
      onSurface: palette.textPrimary,
      onSurfaceVariant: palette.textSecondary,
      error: palette.danger,
      onError: palette.brandOn,
      outline: palette.border,
      outlineVariant: palette.border,
    );

    final textTheme = base.textTheme.copyWith(
      headlineSmall: MdrrmoTypography.displaySm.copyWith(
        color: palette.textPrimary,
      ),
      titleLarge: MdrrmoTypography.titleLg.copyWith(color: palette.textPrimary),
      titleMedium: MdrrmoTypography.titleMd.copyWith(
        color: palette.textPrimary,
      ),
      bodyLarge: MdrrmoTypography.titleMd.copyWith(
        fontWeight: FontWeight.w400,
        color: palette.textPrimary,
      ),
      bodyMedium: MdrrmoTypography.bodyMd.copyWith(color: palette.textPrimary),
      bodySmall: MdrrmoTypography.bodySm.copyWith(
        color: palette.textSecondary,
      ),
      labelLarge: MdrrmoTypography.bodyMd.copyWith(
        fontWeight: FontWeight.w600,
        color: palette.textPrimary,
      ),
      labelMedium: MdrrmoTypography.labelSm.copyWith(
        color: palette.textSecondary,
      ),
      labelSmall: MdrrmoTypography.labelSm.copyWith(color: palette.textMuted),
    );

    return base.copyWith(
      colorScheme: scheme,
      textTheme: textTheme,
      extensions: [palette],
      scaffoldBackgroundColor: palette.canvas,
      canvasColor: palette.surface,
      dividerColor: palette.border,
      dividerTheme: DividerThemeData(
        color: palette.border,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.surface,
        foregroundColor: palette.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: MdrrmoTypography.titleLg.copyWith(
          color: palette.textPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        color: palette.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: palette.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.brand,
          foregroundColor: palette.brandOn,
          disabledBackgroundColor: palette.surfaceSubtle,
          disabledForegroundColor: palette.textMuted,
          elevation: 0,
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          textStyle: MdrrmoTypography.bodyMd.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.textPrimary,
          backgroundColor: palette.surface,
          disabledForegroundColor: palette.textMuted,
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          side: BorderSide(color: palette.borderStrong),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          textStyle: MdrrmoTypography.bodyMd.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.brand,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          textStyle: MdrrmoTypography.bodyMd.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        labelStyle: MdrrmoTypography.bodyMd.copyWith(
          color: palette.textSecondary,
          fontWeight: FontWeight.w500,
        ),
        floatingLabelStyle: MdrrmoTypography.bodySm.copyWith(
          color: palette.brand,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: MdrrmoTypography.bodyMd.copyWith(
          color: palette.textMuted,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: palette.brand, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: palette.danger, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: palette.danger, width: 1.5),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: palette.surface,
        selectedColor: palette.brandTint,
        disabledColor: palette.surfaceSubtle,
        secondarySelectedColor: palette.brandTint,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        labelStyle: MdrrmoTypography.bodySm.copyWith(
          fontWeight: FontWeight.w600,
          color: palette.textPrimary,
        ),
        secondaryLabelStyle: MdrrmoTypography.bodySm.copyWith(
          fontWeight: FontWeight.w700,
          color: palette.isDark
              ? AppColors.onPrimaryContainerDark
              : AppColors.onPrimaryContainerLight,
        ),
        checkmarkColor: palette.brand,
        side: BorderSide(color: palette.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: palette.surface,
        indicatorColor: palette.brandTint,
        elevation: 0,
        height: 64,
        surfaceTintColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: palette.brand, size: 22);
          }
          return IconThemeData(color: palette.textMuted, size: 21);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return MdrrmoTypography.labelSm.copyWith(
              fontWeight: FontWeight.w700,
              color: palette.brand,
            );
          }
          return MdrrmoTypography.labelSm.copyWith(
            fontWeight: FontWeight.w500,
            color: palette.textMuted,
          );
        }),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: palette.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.lg),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: palette.border),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.isDark
            ? AppColors.mutedDark
            : AppColors.foregroundLight,
        contentTextStyle: MdrrmoTypography.bodyMd.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return palette.textMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return palette.brand;
          return palette.surfaceSubtle;
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return palette.brand;
          return Colors.transparent;
        }),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    );
  }
}
