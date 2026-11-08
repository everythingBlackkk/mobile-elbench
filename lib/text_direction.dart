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
TextDirection contentDirection(String text) =>
    contentDirectionOrNull(text) ?? TextDirection.ltr;

/// Like [contentDirection], but null when [text] has no letters or digits.
TextDirection? contentDirectionOrNull(String text) {
  for (final code in text.runes) {
    final ch = String.fromCharCode(code);
    if (_arabicLetter.hasMatch(ch)) return TextDirection.rtl;
    if (_anyLetterOrDigit.hasMatch(ch)) return TextDirection.ltr;
  }
  return null;
}

/// Direction of text that contains mentions: the mentioned names are skipped,
/// so "Sara Adel شكرا" stays right-to-left. Text made only of mentions takes
/// [fallback] (the app's own direction).
TextDirection mentionAwareDirection(
  String text,
  Iterable<String> names,
  TextDirection fallback,
) {
  var rest = text;
  final sorted = names.where((n) => n.isNotEmpty).toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final name in sorted) {
    rest = rest.replaceAll('@$name', ' ').replaceAll(name, ' ');
  }
  return contentDirectionOrNull(rest) ??
      (rest.length == text.length ? contentDirection(text) : fallback);
}

/// A controller that decides its own text direction (see [AdaptiveTextField]).
abstract interface class DirectionalTextController {
  TextDirection textDirection(TextDirection fallback);
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

  TextDirection _measure() {
    final current = controller;
    return current is DirectionalTextController
        ? (current as DirectionalTextController).textDirection(
            Directionality.maybeOf(context) ?? TextDirection.ltr,
          )
        : contentDirection(current.text);
  }

  @override
  void initState() {
    super.initState();
    _direction = contentDirection(controller.text);
    controller.addListener(_recheck);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _direction = _measure();
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
    if (!mounted) return;
    final direction = _measure();
    if (direction != _direction) {
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
