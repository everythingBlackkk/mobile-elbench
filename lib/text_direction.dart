import 'package:flutter/material.dart';

/// Arabic letter ranges: base block, supplements, extended-A, and the two
/// presentation-form blocks used when text arrives shaped from the backend.
final RegExp _arabicLetter = RegExp(
  '[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]',
);

final RegExp _anyLetterOrDigit = RegExp(r'\p{L}|\p{N}', unicode: true);

/// Direction a piece of user content should be laid out in, independent of the
/// app language: RTL when the first letter-like character is Arabic, so a
/// post/comment that starts with Arabic right-aligns even in the English UI.
/// Whitespace, punctuation, digits and emoji are skipped; anything else falls
/// back to LTR.
TextDirection contentDirection(String text) {
  for (final code in text.runes) {
    final ch = String.fromCharCode(code);
    if (_arabicLetter.hasMatch(ch)) return TextDirection.rtl;
    if (_anyLetterOrDigit.hasMatch(ch)) return TextDirection.ltr;
  }
  return TextDirection.ltr;
}

/// A [TextField] that follows the language being typed into it: it rebuilds
/// itself (and only itself) with `textDirection: rtl` as soon as the text
/// starts with an Arabic letter, regardless of the app language.
///
/// Usage:
/// ```dart
/// AdaptiveTextField(
///   controller: input,
///   field: (direction) => TextField(
///     controller: input,
///     textDirection: direction,
///     ...,
///   ),
/// )
/// ```
class AdaptiveTextField extends StatefulWidget {
  const AdaptiveTextField({super.key, required this.field, this.controller});

  /// Builds the underlying field ([TextField] or [TextFormField]); use the
  /// passed direction as the field's `textDirection`.
  final Widget Function(TextDirection direction) field;

  /// When null, an internal controller is created (and disposed) for tracking.
  final TextEditingController? controller;

  @override
  State<AdaptiveTextField> createState() => _AdaptiveTextFieldState();
}

class _AdaptiveTextFieldState extends State<AdaptiveTextField> {
  TextEditingController? _owned;
  late TextDirection _direction;

  TextEditingController get controller =>
      widget.controller ?? (_owned ??= TextEditingController());

  @override
  void initState() {
    super.initState();
    _direction = contentDirection(controller.text);
    controller.addListener(_recheck);
  }

  @override
  void didUpdateWidget(covariant AdaptiveTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller?.removeListener(_recheck);
      controller.addListener(_recheck);
      _recheck();
    }
  }

  void _recheck() {
    final direction = contentDirection(controller.text);
    if (direction != _direction && mounted) {
      setState(() => _direction = direction);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_recheck);
    _owned?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.field(_direction);
}
