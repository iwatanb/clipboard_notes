import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// VisualWhitespaceTextField ---
/// A drop-in replacement for [TextField] that keeps the underlying text intact
/// while visually showing invisible whitespaces:
///   • Half-width space  → "·" (U+00B7 MIDDLE DOT)
///   • Full-width space → "□" (U+25A1 WHITE SQUARE)
///   • Newline          → "↵" (U+21B5 CARRIAGE RETURN ARROW) at end of line
///
/// The widget works by stacking a transparent [CustomPaint] on top of a regular
/// TextField.  The painter looks up the descendant [RenderEditable] to get the
/// layout information, so caret / selection / IME behaviour remain unchanged.
class VisualWhitespaceTextField extends StatefulWidget {
  const VisualWhitespaceTextField({
    super.key,
    required this.controller,
    this.focusNode,
    this.decoration = const InputDecoration(),
    this.minLines,
    this.maxLines,
    this.expands = false,
    this.keyboardType,
    this.style,
    this.textAlignVertical,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final InputDecoration decoration;
  final int? minLines;
  final int? maxLines;
  final bool expands;
  final TextInputType? keyboardType;
  final TextStyle? style;
  final TextAlignVertical? textAlignVertical;

  @override
  State<VisualWhitespaceTextField> createState() =>
      _VisualWhitespaceTextFieldState();
}

class _VisualWhitespaceTextFieldState extends State<VisualWhitespaceTextField> {
  final GlobalKey _textKey = GlobalKey();
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    widget.controller.addListener(_scheduleRepaint);
    _scrollController.addListener(_scheduleRepaint);
  }

  @override
  void didUpdateWidget(covariant VisualWhitespaceTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_scheduleRepaint);
      widget.controller.addListener(_scheduleRepaint);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_scheduleRepaint);
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleRepaint() {
    if (mounted) setState(() {});
  }

  RenderEditable? _findRenderEditable() {
    RenderObject? root = _textKey.currentContext?.findRenderObject();
    if (root == null) return null;
    RenderEditable? result;
    void visitor(RenderObject child) {
      if (child is RenderEditable) {
        result = child;
      } else {
        child.visitChildren(visitor);
      }
    }

    root.visitChildren(visitor);
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final textField = TextField(
      key: _textKey,
      controller: widget.controller,
      focusNode: widget.focusNode,
      decoration: widget.decoration,
      minLines: widget.minLines,
      maxLines: widget.maxLines,
      expands: widget.expands,
      keyboardType: widget.keyboardType,
      style: widget.style,
      textAlignVertical: widget.textAlignVertical,
      scrollController: _scrollController,
    );

    final markerColor =
        (widget.style?.color ??
                DefaultTextStyle.of(context).style.color ??
                Colors.black)
            .withOpacity(0.5);

    return Stack(
      alignment: Alignment.topLeft,
      children: [
        textField,
        IgnorePointer(
          child: CustomPaint(
            painter: _WhitespaceOverlayPainter(
              renderEditableProvider: _findRenderEditable,
              overlayBoxProvider: () =>
                  context.findRenderObject() as RenderBox?,
              textStyle: widget.style ?? DefaultTextStyle.of(context).style,
              color: markerColor,
            ),
          ),
        ),
      ],
    );
  }
}

class _WhitespaceOverlayPainter extends CustomPainter {
  _WhitespaceOverlayPainter({
    required this.renderEditableProvider,
    required this.overlayBoxProvider,
    required this.textStyle,
    required this.color,
  });

  final RenderEditable? Function() renderEditableProvider;
  final RenderBox? Function() overlayBoxProvider;
  final TextStyle textStyle;
  final Color color;

  static const String _halfSpaceMarker = '·';
  static const String _fullSpaceMarker = '□';
  static const String _newlineMarker = '↵';

  @override
  void paint(Canvas canvas, Size size) {
    final renderEditable = renderEditableProvider();
    if (renderEditable == null) return;

    final plainText = renderEditable.text?.toPlainText() ?? '';
    if (plainText.isEmpty) return;

    // Prepare glyph painters once.
    final halfPainter = TextPainter(
      text: TextSpan(
        text: _halfSpaceMarker,
        style: textStyle.copyWith(color: color),
      ),
      textDirection: renderEditable.textDirection,
    )..layout();

    final fullPainter = TextPainter(
      text: TextSpan(
        text: _fullSpaceMarker,
        style: textStyle.copyWith(color: color),
      ),
      textDirection: renderEditable.textDirection,
    )..layout();

    final newlinePainter = TextPainter(
      text: TextSpan(
        text: _newlineMarker,
        style: textStyle.copyWith(color: color),
      ),
      textDirection: renderEditable.textDirection,
    )..layout();

    for (int i = 0; i < plainText.length; i++) {
      final int codeUnit = plainText.codeUnitAt(i);
      if (codeUnit != 0x20 && codeUnit != 0x3000 && codeUnit != 0x0A) continue;

      // Determine character rectangle in RenderEditable coordinates.
      Rect charRect;
      bool rectFromBox = false;
      final boxes = renderEditable.getBoxesForSelection(
        TextSelection(baseOffset: i, extentOffset: i + 1),
      );
      if (boxes.isNotEmpty) {
        charRect = boxes.first.toRect();
        rectFromBox = true; // spaces return width zero but retain height.
      } else {
        // Likely newline – use caret position.
        charRect = renderEditable.getLocalRectForCaret(TextPosition(offset: i));
      }

      // Convert to overlay coordinate system.
      final overlay = overlayBoxProvider();
      if (overlay == null) continue;
      final Offset globalTopLeft = renderEditable.localToGlobal(
        charRect.topLeft,
      );
      Offset localTopLeft = overlay.globalToLocal(globalTopLeft);

      // No additional translation: localToGlobal/globalToLocal already reflect
      // the scroll position of RenderEditable. Removing the manual subtraction
      // prevents double offset and keeps markers aligned during scrolling.

      // Choose appropriate painter.
      final TextPainter glyphPainter = codeUnit == 0x20
          ? halfPainter
          : codeUnit == 0x3000
          ? fullPainter
          : newlinePainter;

      // Compute final position: horizontally & vertically centered in char rect.
      final double lineHeight = charRect.height < 1
          ? renderEditable.preferredLineHeight
          : charRect.height;
      final double dx;
      if (rectFromBox && charRect.width > 0) {
        dx = localTopLeft.dx + (charRect.width - glyphPainter.width) / 2;
      } else {
        dx = localTopLeft.dx;
      }
      final double dy =
          localTopLeft.dy + (lineHeight - glyphPainter.height) / 2;

      glyphPainter.paint(canvas, Offset(dx, dy));
    }
  }

  @override
  bool shouldRepaint(covariant _WhitespaceOverlayPainter oldDelegate) {
    return oldDelegate.renderEditableProvider() != renderEditableProvider() ||
        oldDelegate.textStyle != textStyle ||
        oldDelegate.color != color;
  }
}
