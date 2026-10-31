import 'package:flutter/material.dart';

import 'tokens.dart';
import 'typography.dart';

/// Thème Material 3 commun aux 3 apps, construit uniquement à partir des
/// tokens de la charte. Pas de mode sombre au MVP.
///
/// Règle de contraste (docs/DESIGN.md) : Imperial Red ne sert jamais de
/// couleur de texte sur fond clair ; les textes rouges utilisent Cornell Red.
abstract final class IviaTheme {
  static ThemeData light() {
    // Tous les rôles sont déclarés : un rôle omis prend la valeur d'un autre
    // (ex. secondaryContainer = Cobalt), ce qui casse les contrastes.
    const colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: IviaColors.primary,
      onPrimary: Colors.white,
      primaryContainer: IviaColors.primarySoft,
      onPrimaryContainer: IviaColors.primaryStrong,
      secondary: IviaColors.secondary,
      onSecondary: Colors.white,
      secondaryContainer: IviaColors.secondarySoft,
      onSecondaryContainer: IviaColors.tertiary,
      tertiary: IviaColors.tertiary,
      onTertiary: Colors.white,
      tertiaryContainer: IviaColors.secondarySoft,
      onTertiaryContainer: IviaColors.tertiary,
      error: IviaColors.error,
      onError: Colors.white,
      errorContainer: IviaColors.primarySoft,
      onErrorContainer: IviaColors.error,
      surface: IviaColors.surface,
      onSurface: IviaColors.text,
      onSurfaceVariant: IviaColors.textSecondary,
      surfaceContainerLowest: IviaColors.surface,
      surfaceContainerLow: IviaColors.surface,
      surfaceContainer: IviaColors.backgroundAlt,
      surfaceContainerHigh: IviaColors.surface,
      surfaceContainerHighest: IviaColors.background,
      outline: IviaColors.borderInput,
      outlineVariant: IviaColors.border,
    );
    final textTheme = IviaTextStyles.textTheme;

    const buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(IviaRadius.button)),
    );
    // Boutons pleins et à contour : pilules de 54 dp (maquettes du 2026-10-31).
    const pillShape = StadiumBorder();
    const buttonMinimumSize = Size(64, 54);
    const buttonPadding = EdgeInsets.symmetric(horizontal: IviaSpacing.xxl);
    const largeShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(IviaRadius.large)),
    );

    OutlineInputBorder inputBorder(Color color, {double width = 1}) =>
        OutlineInputBorder(
          borderRadius: const BorderRadius.all(
            Radius.circular(IviaRadius.large),
          ),
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: IviaColors.background,
      fontFamily: IviaTextStyles.fontFamily,
      package: IviaTextStyles.package,
      textTheme: textTheme,
      appBarTheme: AppBarThemeData(
        backgroundColor: IviaColors.background,
        foregroundColor: IviaColors.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: IviaTextStyles.title3,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: buttonMinimumSize,
          padding: buttonPadding,
          shape: pillShape,
          textStyle: IviaTextStyles.button,
          disabledBackgroundColor: IviaColors.border,
          disabledForegroundColor: IviaColors.textMuted,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: IviaColors.primaryStrong,
          backgroundColor: IviaColors.surface,
          minimumSize: buttonMinimumSize,
          padding: buttonPadding,
          shape: pillShape,
          textStyle: IviaTextStyles.button,
          side: const BorderSide(color: IviaColors.borderInput),
          disabledForegroundColor: IviaColors.textMuted,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: IviaColors.primaryStrong,
          minimumSize: const Size(48, 48),
          shape: buttonShape,
          textStyle: IviaTextStyles.button,
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: IviaColors.surface,
        contentPadding: const EdgeInsets.all(IviaSpacing.lg),
        hintStyle: IviaTextStyles.body.copyWith(color: IviaColors.textMuted),
        floatingLabelStyle: WidgetStateTextStyle.resolveWith(
          (states) => IviaTextStyles.body.copyWith(
            color: states.contains(WidgetState.error)
                ? IviaColors.error
                : states.contains(WidgetState.focused)
                ? IviaColors.primaryStrong
                : IviaColors.textSecondary,
          ),
        ),
        border: inputBorder(IviaColors.borderInput),
        enabledBorder: inputBorder(IviaColors.borderInput),
        focusedBorder: inputBorder(IviaColors.primary, width: 2),
        errorBorder: inputBorder(IviaColors.error),
        focusedErrorBorder: inputBorder(IviaColors.error, width: 2),
        disabledBorder: inputBorder(IviaColors.border),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(IviaRadius.tile)),
        ),
        side: const BorderSide(color: IviaColors.borderInput, width: 1.5),
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? IviaColors.primary
              : IviaColors.surface,
        ),
        checkColor: const WidgetStatePropertyAll(Colors.white),
      ),
      cardTheme: const CardThemeData(
        color: IviaColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: largeShape,
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: const BorderSide(color: IviaColors.border),
        backgroundColor: IviaColors.surface,
        selectedColor: IviaColors.secondarySoft,
        checkmarkColor: IviaColors.tertiary,
        labelStyle: textTheme.labelMedium,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: IviaColors.primaryStrong,
        unselectedLabelColor: IviaColors.textSecondary,
        indicatorColor: IviaColors.primary,
        labelStyle: IviaTextStyles.bodyStrong,
        unselectedLabelStyle: IviaTextStyles.body,
        dividerColor: IviaColors.border,
      ),
      // Pas d'ombre sur les feuilles modales du thème : le voile sombre les
      // détache déjà. `IviaShadows.sheet` sert aux feuilles non modales.
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: IviaColors.surface,
        elevation: 0,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(IviaRadius.large),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: IviaColors.surface,
        elevation: 0,
        indicatorColor: IviaColors.secondarySoft,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? IviaColors.tertiary
                : IviaColors.textSecondary,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? IviaTextStyles.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: IviaColors.text,
                )
              : IviaTextStyles.caption.copyWith(
                  color: IviaColors.textSecondary,
                ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: IviaColors.border,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: IviaColors.berkeleyBlue,
        contentTextStyle: IviaTextStyles.body.copyWith(color: Colors.white),
        shape: buttonShape,
      ),
    );
  }
}
