import 'package:flutter/material.dart';
import 'package:nochy_eat/theme/app_colors.dart';

/// Presentation tokens used only by driver-facing screens.
/// AppColors remains untouched because customer and seller reuse it.
class DriverUi {
  static const pagePadding = EdgeInsets.symmetric(horizontal: 16);
  static const sectionGap = SizedBox(height: 20);
  static const itemGap = SizedBox(height: 12);

  static const Radius cardRadius = Radius.circular(14);
  static const Radius controlRadius = Radius.circular(10);

  static const blueTint = Color(0xFFE7F6FC);
  static const greenTint = Color(0xFFE8F5E9);
  static const orangeTint = Color(0xFFFFF3E0);
  static const border = Color(0xFFE0E0E0);
  static const mutedText = Color(0xFF616161);

  static const contentTitle = TextStyle(
    fontSize: 18,
    height: 1.2,
    fontWeight: FontWeight.w800,
    color: AppColors.textDark,
  );

  static const sectionTitle = TextStyle(
    fontSize: 15,
    height: 1.25,
    fontWeight: FontWeight.w800,
    color: AppColors.textDark,
  );

  static const body = TextStyle(
    fontSize: 12,
    height: 1.35,
    color: mutedText,
  );

  static BoxDecoration surface({Color color = Colors.white}) {
    return BoxDecoration(
      color: color,
      borderRadius: const BorderRadius.all(cardRadius),
      border: const Border.fromBorderSide(BorderSide(color: border)),
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

  static InputDecoration inputDecoration({
    required String hintText,
    required Widget prefixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(color: mutedText, fontSize: 13),
      prefixIcon: prefixIcon,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 13),
      enabledBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(controlRadius),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(controlRadius),
        borderSide: BorderSide(color: AppColors.primaryPink, width: 2),
      ),
    );
  }
}
