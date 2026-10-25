import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Rounds transport percentages down without floating-point boundary artifacts.
/// Only a completed byte transfer may display 100%.
int? uploadProgressPercent(double? value) {
  if (value == null || !value.isFinite) return null;
  final progress = value.clamp(0.0, 1.0);
  if (progress >= 1) return 100;
  return math.min(99, (progress * 100 + 1e-9).floor());
}

/// Displays transport progress while the caller waits for the server response.
/// A full bar means the bytes were sent; the upload is still being finalized.
class UploadProgressIndicator extends StatelessWidget {
  const UploadProgressIndicator({
    super.key,
    required this.value,
    required this.label,
    required this.finishingLabel,
  });

  final double? value;
  final String label, finishingLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = value?.isFinite == true ? value!.clamp(0.0, 1.0) : null;
    final percentage = uploadProgressPercent(progress);
    final percent = percentage == null ? null : '$percentage%';
    final status = progress == 1 ? finishingLabel : label;

    return Semantics(
      container: true,
      label: status,
      value: percent,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      status,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  if (percent != null) ...[
                    const SizedBox(width: 12),
                    Text(
                      percent,
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: scheme.primary,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                borderRadius: BorderRadius.circular(999),
                color: scheme.primary,
                backgroundColor: scheme.outlineVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
