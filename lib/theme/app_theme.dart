import 'package:flutter/material.dart';

/// Identidade visual do Partituras: "a estante e o lápis".
///
/// - Tinta (grafite azulado) para texto e para o fundo do leitor.
/// - Papel (branco frio) para a biblioteca.
/// - Azul de edição como cor de ação/seleção.
/// - Vermelho de lápis reservado para anotações e favoritas.
///
/// Escala tipográfica compacta, pensada para desktop (Windows usa Segoe UI).
abstract final class AppColors {
  static const ink = Color(0xFF1E2533);
  static const paper = Color(0xFFF5F6F8);
  static const editionBlue = Color(0xFF2B4C8C);
  static const pencilRed = Color(0xFFB3312A);
  static const graphite = Color(0xFF5E6675);
  static const highlighter = Color(0xFFF0C02F);
}

/// Espaçamentos em múltiplos de 4.
abstract final class Space {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

abstract final class Radii {
  static const sm = 6.0;
  static const md = 8.0;
  static const lg = 12.0;
}

/// Tokens que o Material não tem lugar para guardar.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.readerBackground,
    required this.readerChrome,
    required this.onReaderChrome,
    required this.pageShadow,
    required this.favorite,
  });

  /// Fundo atrás das páginas no leitor.
  final Color readerBackground;

  /// Barra superior do leitor.
  final Color readerChrome;
  final Color onReaderChrome;
  final Color pageShadow;

  /// Cor da marca de favorita (vermelho do lápis).
  final Color favorite;

  static const light = AppTokens(
    readerBackground: Color(0xFF2A3140),
    readerChrome: AppColors.ink,
    onReaderChrome: Color(0xFFE3E6EC),
    pageShadow: Color(0x66000000),
    favorite: AppColors.pencilRed,
  );

  static const dark = AppTokens(
    readerBackground: Color(0xFF12161D),
    readerChrome: Color(0xFF1B212B),
    onReaderChrome: Color(0xFFE3E6EC),
    pageShadow: Color(0x99000000),
    favorite: Color(0xFFE5675F),
  );

  @override
  AppTokens copyWith({
    Color? readerBackground,
    Color? readerChrome,
    Color? onReaderChrome,
    Color? pageShadow,
    Color? favorite,
  }) => AppTokens(
    readerBackground: readerBackground ?? this.readerBackground,
    readerChrome: readerChrome ?? this.readerChrome,
    onReaderChrome: onReaderChrome ?? this.onReaderChrome,
    pageShadow: pageShadow ?? this.pageShadow,
    favorite: favorite ?? this.favorite,
  );

  @override
  AppTokens lerp(AppTokens? other, double t) {
    if (other == null) return this;
    return AppTokens(
      readerBackground: Color.lerp(readerBackground, other.readerBackground, t)!,
      readerChrome: Color.lerp(readerChrome, other.readerChrome, t)!,
      onReaderChrome: Color.lerp(onReaderChrome, other.onReaderChrome, t)!,
      pageShadow: Color.lerp(pageShadow, other.pageShadow, t)!,
      favorite: Color.lerp(favorite, other.favorite, t)!,
    );
  }
}

extension AppThemeX on BuildContext {
  AppTokens get tokens => Theme.of(this).extension<AppTokens>()!;
}

abstract final class AppTheme {
  static final light = _build(_lightScheme, AppTokens.light);
  static final dark = _build(_darkScheme, AppTokens.dark);

  static const _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.editionBlue,
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFDCE4F5),
    onPrimaryContainer: Color(0xFF12264D),
    secondary: AppColors.graphite,
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFE3E7EE),
    onSecondaryContainer: AppColors.ink,
    tertiary: AppColors.pencilRed,
    onTertiary: Colors.white,
    error: AppColors.pencilRed,
    onError: Colors.white,
    surface: AppColors.paper,
    onSurface: AppColors.ink,
    onSurfaceVariant: AppColors.graphite,
    outline: Color(0xFFA3AAB7),
    outlineVariant: Color(0xFFDDE1E8),
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Color(0xFFEFF1F4),
    surfaceContainer: Color(0xFFEAECF0),
    surfaceContainerHigh: Color(0xFFE4E7EC),
    surfaceContainerHighest: Color(0xFFDEE2E8),
    inverseSurface: AppColors.ink,
    onInverseSurface: Color(0xFFE3E6EC),
    inversePrimary: Color(0xFFA9C1F2),
    shadow: Colors.black,
    scrim: Colors.black,
    surfaceTint: Colors.transparent,
  );

  static const _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFA9C1F2),
    onPrimary: Color(0xFF10284F),
    primaryContainer: AppColors.editionBlue,
    onPrimaryContainer: Color(0xFFDCE4F5),
    secondary: Color(0xFFA3AAB7),
    onSecondary: Color(0xFF1E2533),
    secondaryContainer: Color(0xFF2E3542),
    onSecondaryContainer: Color(0xFFE3E6EC),
    tertiary: Color(0xFFE5675F),
    onTertiary: Color(0xFF3A0B08),
    error: Color(0xFFF2867E),
    onError: Color(0xFF3A0B08),
    surface: Color(0xFF161B24),
    onSurface: Color(0xFFE3E6EC),
    onSurfaceVariant: Color(0xFFA3AAB7),
    outline: Color(0xFF6B7383),
    outlineVariant: Color(0xFF2C3340),
    surfaceContainerLowest: Color(0xFF11151C),
    surfaceContainerLow: Color(0xFF1B212B),
    surfaceContainer: Color(0xFF1F2530),
    surfaceContainerHigh: Color(0xFF262D39),
    surfaceContainerHighest: Color(0xFF2E3542),
    inverseSurface: Color(0xFFE3E6EC),
    onInverseSurface: AppColors.ink,
    inversePrimary: AppColors.editionBlue,
    shadow: Colors.black,
    scrim: Colors.black,
    surfaceTint: Colors.transparent,
  );

  /// Escala compacta para desktop. O padrão do Material 3 (corpo 16,
  /// título 22) é dimensionado para celular e fica grande no Windows.
  static TextTheme _textTheme(Color color, Color muted) {
    TextStyle s(double size, FontWeight weight, double height, [double spacing = 0]) =>
        TextStyle(fontSize: size, fontWeight: weight, height: height, letterSpacing: spacing, color: color);
    return TextTheme(
      displayLarge: s(40, FontWeight.w600, 1.15, -0.5),
      displayMedium: s(32, FontWeight.w600, 1.15, -0.4),
      displaySmall: s(26, FontWeight.w600, 1.2, -0.3),
      headlineLarge: s(24, FontWeight.w600, 1.25, -0.2),
      headlineMedium: s(20, FontWeight.w600, 1.3, -0.1),
      headlineSmall: s(18, FontWeight.w600, 1.3),
      titleLarge: s(17, FontWeight.w600, 1.3),
      titleMedium: s(14, FontWeight.w600, 1.35),
      titleSmall: s(13, FontWeight.w600, 1.35),
      bodyLarge: s(14, FontWeight.w400, 1.45),
      bodyMedium: s(13, FontWeight.w400, 1.45),
      bodySmall: s(12, FontWeight.w400, 1.4).copyWith(color: muted),
      labelLarge: s(13, FontWeight.w600, 1.2),
      labelMedium: s(12, FontWeight.w500, 1.2),
      labelSmall: s(11, FontWeight.w500, 1.2).copyWith(color: muted),
    );
  }

  static ThemeData _build(ColorScheme c, AppTokens tokens) {
    final text = _textTheme(c.onSurface, c.onSurfaceVariant);
    final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md));
    OutlineInputBorder inputBorder(Color color, [double width = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(Radii.md),
      borderSide: BorderSide(color: color, width: width),
    );

    return ThemeData(
      colorScheme: c,
      scaffoldBackgroundColor: c.surface,
      textTheme: text,
      visualDensity: VisualDensity.compact,
      extensions: [tokens],
      // Ícones Material Symbols (traço fino) — ver lib/theme/app_icons.dart.
      iconTheme: IconThemeData(size: 20, weight: 300, opticalSize: 20, color: c.onSurfaceVariant),
      appBarTheme: AppBarThemeData(
        backgroundColor: c.surface,
        foregroundColor: c.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 60,
        titleSpacing: Space.xl,
        titleTextStyle: text.headlineSmall,
        actionsIconTheme: IconThemeData(size: 20, weight: 300, opticalSize: 20, color: c.onSurfaceVariant),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        isDense: true,
        filled: true,
        fillColor: c.surfaceContainerLowest,
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 10),
        hintStyle: text.bodyMedium?.copyWith(color: c.onSurfaceVariant.withValues(alpha: 0.8)),
        labelStyle: text.bodyMedium?.copyWith(color: c.onSurfaceVariant),
        floatingLabelStyle: text.labelMedium?.copyWith(color: c.primary),
        prefixIconColor: c.onSurfaceVariant,
        suffixIconColor: c.onSurfaceVariant,
        prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        suffixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        border: inputBorder(c.outlineVariant),
        enabledBorder: inputBorder(c.outlineVariant),
        hoverColor: c.surfaceContainerLow,
        focusedBorder: inputBorder(c.primary, 1.5),
        errorBorder: inputBorder(c.error),
        focusedErrorBorder: inputBorder(c.error, 1.5),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: rounded,
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: Space.lg),
          textStyle: text.labelLarge,
          iconSize: 18,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: rounded,
          minimumSize: const Size(0, 36),
          side: BorderSide(color: c.outlineVariant),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: rounded, minimumSize: const Size(0, 36), textStyle: text.labelLarge),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: rounded,
          iconSize: 20,
          minimumSize: const Size(36, 36),
          foregroundColor: c.onSurfaceVariant,
          highlightColor: c.primary.withValues(alpha: 0.1),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          shape: rounded,
          side: BorderSide(color: c.outlineVariant),
          selectedBackgroundColor: c.primaryContainer,
          selectedForegroundColor: c.onPrimaryContainer,
          foregroundColor: c.onSurfaceVariant,
          iconSize: 18,
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm)),
        side: BorderSide(color: c.outlineVariant),
        backgroundColor: c.surfaceContainerLowest,
        selectedColor: c.primaryContainer,
        labelStyle: text.labelMedium,
        secondaryLabelStyle: text.labelMedium?.copyWith(color: c.onPrimaryContainer),
        padding: const EdgeInsets.symmetric(horizontal: Space.xs),
        iconTheme: IconThemeData(size: 16, weight: 300, color: c.onSurfaceVariant),
        showCheckmark: false,
      ),
      cardTheme: CardThemeData(
        color: c.surfaceContainerLowest,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
          side: BorderSide(color: c.outlineVariant),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
        titleTextStyle: text.headlineSmall,
        contentTextStyle: text.bodyMedium,
        actionsPadding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.lg),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surfaceContainerLowest,
        elevation: 6,
        shadowColor: Colors.black26,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          side: BorderSide(color: c.outlineVariant),
        ),
        labelTextStyle: WidgetStatePropertyAll(text.bodyMedium),
        menuPadding: const EdgeInsets.symmetric(vertical: Space.xs),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        textStyle: text.labelMedium?.copyWith(color: c.onInverseSurface),
        decoration: BoxDecoration(color: c.inverseSurface, borderRadius: BorderRadius.circular(Radii.sm)),
        padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xs),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        width: 420,
        backgroundColor: c.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(color: c.onInverseSurface),
        shape: rounded,
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        activeTrackColor: c.primary,
        inactiveTrackColor: c.outlineVariant,
      ),
      switchTheme: SwitchThemeData(
        thumbIcon: const WidgetStatePropertyAll(null),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.transparent : c.outline,
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbVisibility: const WidgetStatePropertyAll(true),
        thickness: const WidgetStatePropertyAll(6),
        radius: const Radius.circular(3),
        thumbColor: WidgetStatePropertyAll(c.outline.withValues(alpha: 0.5)),
      ),
      dividerTheme: DividerThemeData(color: c.outlineVariant, space: 1, thickness: 1),
      listTileTheme: ListTileThemeData(
        dense: true,
        shape: rounded,
        iconColor: c.onSurfaceVariant,
        titleTextStyle: text.bodyMedium,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.primary),
      focusColor: c.primary.withValues(alpha: 0.12),
      hoverColor: c.onSurface.withValues(alpha: 0.05),
    );
  }
}
