import 'package:flutter/material.dart';

/// Marks a theme as the Windows desktop shell's, so the pages shared with
/// the phone can lay themselves out and word themselves for a PC: setting
/// cards instead of phone rows, "this PC" instead of "this phone", click
/// instead of tap. Only `DesktopTheme` adds it; the phone never sees it.
@immutable
class FormFactor extends ThemeExtension<FormFactor> {
  final bool desktop;
  const FormFactor({required this.desktop});

  static const pc = FormFactor(desktop: true);

  @override
  FormFactor copyWith({bool? desktop}) =>
      FormFactor(desktop: desktop ?? this.desktop);

  @override
  FormFactor lerp(FormFactor? other, double t) =>
      t < 0.5 ? this : other ?? this;
}

extension FormFactorX on BuildContext {
  /// True inside the desktop shell.
  bool get isDesktop =>
      Theme.of(this).extension<FormFactor>()?.desktop ?? false;

  /// [phone] on the phone, [desktop] on the PC: for wording that names the
  /// device or a touch gesture.
  T byFormFactor<T>(T phone, T desktop) => isDesktop ? desktop : phone;
}
