import 'package:flutter/material.dart';
import 'package:nochy_eat/theme/app_colors.dart';

/// Presentation tokens used only by customer-facing screens.
/// AppColors remains untouched because seller and driver reuse it.
class CustomerUi {
  static const pagePadding = EdgeInsets.symmetric(horizontal: 16);
  static const sectionGap = SizedBox(height: 24);
  static const itemGap = SizedBox(height: 12);

  static const Radius cardRadius = Radius.circular(16);
  static const Radius controlRadius = Radius.circular(12);

  static const pinkTint = Color(0xFFFCE7F5);
  static const blueTint = Color(0xFFE7F6FC);
  static const yellowTint = Color(0xFFFFFAD8);
  static const border = Color(0xFFE6E1E4);
  static const mutedText = Color(0xFF625C5F);

  static const contentTitle = TextStyle(
    fontSize: 18,
    height: 1.2,
    fontWeight: FontWeight.w800,
    color: AppColors.textDark,
  );

  static const sectionTitle = TextStyle(
    fontSize: 16,
    height: 1.25,
    fontWeight: FontWeight.w800,
    color: AppColors.textDark,
  );

  static const body = TextStyle(
    fontSize: 13,
    height: 1.35,
    color: mutedText,
  );

  static BoxDecoration surface({
    Color color = Colors.white,
    bool outlined = true,
    Border? border,
  }) {
    return BoxDecoration(
      color: color,
      borderRadius: const BorderRadius.all(cardRadius),
      border: border ??
          (outlined
              ? const Border.fromBorderSide(BorderSide(color: CustomerUi.border))
              : null),
    );
  }

  static ButtonStyle primaryButton = ElevatedButton.styleFrom(
    backgroundColor: AppColors.primaryPink,
    foregroundColor: Colors.white,
    elevation: 0,
    minimumSize: const Size(44, 44),
    padding: const EdgeInsets.symmetric(horizontal: 16),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(controlRadius),
    ),
    textStyle: const TextStyle(fontWeight: FontWeight.w800),
  );

  static InputDecoration searchDecoration({
    required String hintText,
    required Widget prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(color: mutedText, fontSize: 13),
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 13),
      enabledBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(controlRadius),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(controlRadius),
        borderSide: BorderSide(color: AppColors.accentBlue, width: 2),
      ),
    );
  }
}
