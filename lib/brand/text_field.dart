import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/theme.dart';

/// The mockups' input: a 54px rounded field on the surface color with a
/// leading icon and the hint as its only label.
class BrandTextField extends StatelessWidget {
  const BrandTextField({
    super.key,
    required this.icon,
    required this.hint,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.inputFormatters,
    this.obscureText = false,
    this.autofocus = false,
    this.enabled = true,
  });

  final IconData icon;
  final String hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final bool obscureText;
  final bool autofocus;
  final bool enabled;

  static final _border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(BrandRadii.md),
    borderSide: const BorderSide(color: BrandColors.line),
  );

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    onChanged: onChanged,
    onSubmitted: onSubmitted,
    keyboardType: keyboardType,
    textInputAction: textInputAction,
    autofillHints: autofillHints,
    inputFormatters: inputFormatters,
    obscureText: obscureText,
    autocorrect: !obscureText,
    autofocus: autofocus,
    enabled: enabled,
    style: BrandText.body,
    cursorColor: BrandColors.accent,
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: BrandText.hint,
      filled: true,
      fillColor: BrandColors.surface,
      prefixIcon: Icon(icon, size: 20, color: BrandColors.muted),
      contentPadding: const EdgeInsets.symmetric(vertical: 16),
      border: _border,
      enabledBorder: _border,
      disabledBorder: _border,
      focusedBorder: _border.copyWith(
        borderSide: const BorderSide(color: BrandColors.accent),
      ),
    ),
  );
}
