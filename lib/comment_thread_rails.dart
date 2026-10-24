import 'package:flutter/material.dart';

/// Rails are painted behind content so multiline comments size them naturally.
class CommentThreadRail extends StatelessWidget {
  const CommentThreadRail({
    super.key,
    required this.visible,
    required this.color,
    required this.child,
    this.top = 54,
  });
  final bool visible;
  final Color color;
  final Widget child;
  final double top;
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: visible
        ? _ThreadRailPainter(
            color: color,
            direction: Directionality.of(context),
            top: top,
          )
        : null,
    child: child,
  );
}

class CommentReplyBranch extends StatelessWidget {
  const CommentReplyBranch({
    super.key,
    required this.continues,
    required this.color,
    required this.child,
  });
  final bool continues;
  final Color color;
  final Widget child;
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _ReplyBranchPainter(
      color: color,
      direction: Directionality.of(context),
      continues: continues,
    ),
    child: Padding(
      padding: const EdgeInsetsDirectional.only(start: 32),
      child: child,
    ),
  );
}

class _ThreadRailPainter extends CustomPainter {
  const _ThreadRailPainter({
    required this.color,
    required this.direction,
    required this.top,
  });
  final Color color;
  final TextDirection direction;
  final double top;
  @override
  void paint(Canvas canvas, Size size) {
    if (size.height <= top) return;
    final x = direction == TextDirection.ltr ? 21.0 : size.width - 21;
    canvas.drawLine(
      Offset(x, top),
      Offset(x, size.height),
      Paint()
        ..color = color
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ThreadRailPainter old) =>
      old.color != color || old.direction != direction || old.top != top;
}

class _ReplyBranchPainter extends CustomPainter {
  const _ReplyBranchPainter({
    required this.color,
    required this.direction,
    required this.continues,
  });
  final Color color;
  final TextDirection direction;
  final bool continues;
  @override
  void paint(Canvas canvas, Size size) {
    final rtl = direction == TextDirection.rtl;
    final x = rtl ? size.width - 21 : 21.0;
    final sign = rtl ? -1.0 : 1.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    if (continues) canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    final branch = Path()
      ..moveTo(x, 0)
      ..lineTo(x, 19)
      ..quadraticBezierTo(x, 27, x + sign * 8, 27)
      // Stop at the reply avatar's edge, including translucent placeholders.
      ..lineTo(x + sign * 11, 27);
    canvas.drawPath(branch, paint);
  }

  @override
  bool shouldRepaint(_ReplyBranchPainter old) =>
      old.color != color ||
      old.direction != direction ||
      old.continues != continues;
}
