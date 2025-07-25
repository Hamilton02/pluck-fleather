import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pluck_parchment/parchment.dart';

import '../widgets/cursor.dart';
import '../widgets/selection_utils.dart';
import '../widgets/theme.dart';
import 'cursor_painter.dart';
import 'editable_box.dart';

const double _kCursorHeightOffset = 2.0; // pixels

enum TextLineSlot { leading, body }

class RenderEditableTextLine extends RenderEditableBox {
  /// Creates new editable paragraph render box.
  RenderEditableTextLine({
    required LineNode node,
    required EdgeInsetsGeometry padding,
    required TextDirection textDirection,
    required CursorController cursorController,
    required TextSelection selection,
    required Color selectionColor,
    required bool enableInteractiveSelection,
    required bool hasFocus,
    required InlineCodeThemeData inlineCodeTheme,
    double devicePixelRatio = 1.0,
    // Not implemented fields are below:
    ui.BoxHeightStyle selectionHeightStyle = ui.BoxHeightStyle.tight,
    ui.BoxWidthStyle selectionWidthStyle = ui.BoxWidthStyle.tight,
    EdgeInsets floatingCursorAddedMargin =
        const EdgeInsets.fromLTRB(4, 4, 4, 5),
  })  : assert(padding.isNonNegative),
        _textDirection = textDirection,
        _padding = padding,
        _node = node,
        _cursorController = cursorController,
        _selection = selection,
        _selectionColor = selectionColor,
        _enableInteractiveSelection = enableInteractiveSelection,
        _devicePixelRatio = devicePixelRatio,
        _inlineCodeTheme = inlineCodeTheme,
        _hasFocus = hasFocus;

  //

  InlineCodeThemeData _inlineCodeTheme;

  set inlineCodeTheme(InlineCodeThemeData theme) {
    if (_inlineCodeTheme == theme) return;
    _inlineCodeTheme = theme;
    markNeedsLayout();
  }

  // Start selection implementation

  List<TextBox>? _selectionRects;

  /// The region of text that is selected, if any.
  ///
  /// The caret position is represented by a collapsed selection.
  ///
  /// If [selection] is null, there is no selection and attempts to
  /// manipulate the selection will throw.
  TextSelection get selection => _selection;
  TextSelection _selection;

  set selection(TextSelection value) {
    if (_selection == value) return;
    final hadSelection = containsSelection;
    if (_attachedToCursorController) {
      _cursorController.removeListener(markNeedsLayout);
      _cursorController.cursorColor.removeListener(markNeedsPaint);
      _attachedToCursorController = false;
    }
    _selection = value;
    _selectionRects = null;
    if (attached && containsCursor) {
      _cursorController.addListener(markNeedsLayout);
      _cursorController.cursorColor.addListener(markNeedsPaint);
      _attachedToCursorController = true;
    }

    if (hadSelection || containsSelection) {
      markNeedsPaint();
    }
  }

  /// The color to use when painting the selection.
  Color get selectionColor => _selectionColor;
  Color _selectionColor;

  set selectionColor(Color value) {
    if (_selectionColor == value) return;
    _selectionColor = value;
    if (containsSelection) markNeedsPaint();
  }

  /// Whether to allow the user to change the selection.
  ///
  /// Since this render object does not handle selection manipulation
  /// itself, this actually only affects whether the accessibility
  /// hints provided to the system (via
  /// [describeSemanticsConfiguration]) will enable selection
  /// manipulation. It's the responsibility of this object's owner
  /// to provide selection manipulation affordances.
  ///
  /// This field is used by [_shouldPaintSelection] (which then controls
  /// the accessibility hints mentioned above).
  bool get enableInteractiveSelection => _enableInteractiveSelection;
  bool _enableInteractiveSelection;

  set enableInteractiveSelection(bool value) {
    if (_enableInteractiveSelection == value) return;
    _enableInteractiveSelection = value;
    markNeedsTextLayout();
    markNeedsSemanticsUpdate(); // TODO: should probably update semantics on the RenderEditor instead.
  }

  /// Whether selection should be painted based on the value of
  /// [enableInteractiveSelection] and [hasFocus].
  ///
  /// If [enableInteractiveSelection] is not set then defaults to `true`.
  bool get _shouldPaintSelection => enableInteractiveSelection && hasFocus;

  bool get containsSelection => intersectsWithSelection(node, _selection);

  // End selection implementation

  //

  /// Whether the editor is currently focused.
  bool get hasFocus => _hasFocus;
  bool _hasFocus = false;

  set hasFocus(bool value) {
    if (_hasFocus == value) {
      return;
    }
    _hasFocus = value;
    markNeedsPaint();
  }

  /// The pixel ratio of the current device.
  ///
  /// Should be obtained by querying MediaQuery for the devicePixelRatio.
  double get devicePixelRatio => _devicePixelRatio;
  double _devicePixelRatio;

  set devicePixelRatio(double value) {
    if (devicePixelRatio == value) return;
    _devicePixelRatio = value;
    markNeedsTextLayout();
  }

  final Map<TextLineSlot, RenderBox> children = <TextLineSlot, RenderBox>{};

  // The returned list is ordered for hit testing.
  Iterable<RenderBox> get _children sync* {
    if (_leading != null) {
      yield _leading!;
    }
    if (_body != null) {
      yield _body!;
    }
  }

  RenderBox? get leading => _leading;
  RenderBox? _leading;

  set leading(RenderBox? value) {
    _leading = _updateChild(_leading, value, TextLineSlot.leading);
  }

  RenderContentProxyBox? get body => _body;
  RenderContentProxyBox? _body;

  set body(RenderContentProxyBox? value) {
    _body =
        _updateChild(_body, value, TextLineSlot.body) as RenderContentProxyBox?;
  }

  RenderBox? _updateChild(
      RenderBox? oldChild, RenderBox? newChild, TextLineSlot slot) {
    if (oldChild != null) {
      dropChild(oldChild);
      children.remove(slot);
    }
    if (newChild != null) {
      children[slot] = newChild;
      adoptChild(newChild);
    }
    return newChild;
  }

  // Start RenderEditableBox implementation

  @override
  LineNode get node => _node;
  LineNode _node;

  set node(LineNode value) {
    if (_node == value) {
      return;
    }
    _node = value;
    markNeedsLayout();
  }

  /// The text direction with which to resolve [padding].
  ///
  /// This may be changed to null, but only after the [padding] has been changed
  /// to a value that does not depend on the direction.
  TextDirection get textDirection => _textDirection;
  TextDirection _textDirection;

  set textDirection(TextDirection value) {
    if (_textDirection == value) {
      return;
    }
    _textDirection = value;
    _markNeedsPaddingResolution();
  }

  @override
  double preferredLineHeight(TextPosition position) {
    // For single line nodes this value is constant because we're using the same
    // text painter.
    return body!.preferredLineHeight;
  }

  /// The [position] parameter is expected to be relative to the [node] content.
  @override
  Offset getOffsetForCaret(TextPosition position) {
    final parentData = body!.parentData as BoxParentData;
    return body!.getOffsetForCaret(position, _caretPrototype) +
        parentData.offset;
  }

  @override
  Rect getLocalRectForCaret(TextPosition position) {
    final caretOffset = getOffsetForCaret(position);
    var rect =
        Rect.fromLTWH(0.0, 0.0, cursorWidth, cursorHeight).shift(caretOffset);
    final cursorOffset = _cursorController.style.offset;
    // Add additional cursor offset (generally only if on iOS).
    if (cursorOffset != null) rect = rect.shift(cursorOffset);
    return rect;
  }

  @override
  Rect getCaretPrototype(TextPosition position) => _caretPrototype;

  @override
  TextPosition globalToLocalPosition(TextPosition position) {
    assert(node.containsOffset(position.offset),
        'The provided text position is not in the current node');
    return TextPosition(
      offset: position.offset - node.documentOffset,
      affinity: position.affinity,
    );
  }

  /// The [offset] parameter is expected to be local coordinates of this render
  /// object.
  @override
  TextPosition getPositionForOffset(Offset offset) {
    final parentData = body!.parentData as BoxParentData;
    final shiftedOffset = offset - parentData.offset;
    return body!.getPositionForOffset(shiftedOffset);
  }

  // Computes the line box height for the position.
  double _getLineHeightForPosition(TextPosition position) {
    final lineBoundary = getLineBoundary(position);
    var boxes = body!.getBoxesForSelection(TextSelection(
        baseOffset: lineBoundary.start, extentOffset: lineBoundary.end));
    // Boxes are empty for an empty line (containing only \n)
    if (boxes.isEmpty && lineBoundary == const TextRange.collapsed(0)) {
      boxes = body!.getBoxesForSelection(TextSelection(
          baseOffset: lineBoundary.start, extentOffset: lineBoundary.end + 1));
    }
    return boxes.fold(0, (v, e) => math.max(v, e.toRect().height));
  }

  @override
  TextPosition? getPositionAbove(TextPosition position) {
    assert(position.offset < node.length);
    final parentData = body!.parentData as BoxParentData;

    // The caret offset gives a location in the upper left hand corner of
    // the caret so the middle of the line above is a half line above that
    // point.
    final caretOffset = getOffsetForCaret(position);
    final dy = -_getLineHeightForPosition(position) +
        0.5 * preferredLineHeight(position);
    final abovePositionOffset = caretOffset.translate(0, dy);
    if (!body!.size.contains(abovePositionOffset - parentData.offset)) {
      // We're outside of the body so there is no text above to check.
      return null;
    }
    return getPositionForOffset(abovePositionOffset);
  }

  @override
  TextPosition? getPositionBelow(TextPosition position) {
    assert(position.offset < node.length);
    final parentData = body!.parentData as BoxParentData;

    // The caret offset gives a location in the upper left hand corner of
    // the caret so the middle of the line below is 1.5 lines below that
    // point.
    final caretOffset = getOffsetForCaret(position);
    final dy = 1.5 * preferredLineHeight(position);
    final belowPositionOffset = caretOffset.translate(0, dy);
    if (!body!.size.contains(belowPositionOffset - parentData.offset)) {
      // We're outside of the body so there is no text below to check.
      return null;
    }
    return getPositionForOffset(belowPositionOffset);
  }

  @override
  TextRange getWordBoundary(TextPosition position) {
    return body!.getWordBoundary(position);
  }

  @override
  TextRange getLineBoundary(TextPosition position) {
    // getOffsetForCaret returns top-left corner of the caret. To find all
    // selection boxes on the same line we shift caret offset by 0.5 of
    // preferredLineHeight so that it's in the middle of the line and filter out
    // boxes which do not include this offset on the Y axis.
    final caret = getOffsetForCaret(position);
    final lineDy = caret.translate(0.0, 0.5 * preferredLineHeight(position)).dy;
    final boxes = getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: node.length - 1));

    // If document is empty, boxes will be empty
    // TextPainter (RenderParagraphProxy -> RenderParagraph) returns no boxes
    // when it has not text
    if (boxes.isEmpty) return const TextRange.collapsed(0);

    final lineBoxes = boxes
        .where((element) => element.top < lineDy && element.bottom > lineDy)
        .toList(growable: false);
    final start = getPositionForOffset(Offset(lineBoxes.first.left, lineDy));
    final end = getPositionForOffset(Offset(lineBoxes.last.right, lineDy));
    return TextRange(start: start.offset, end: end.offset);
  }

  @override
  TextSelectionPoint getBaseEndpointForSelection(TextSelection selection) {
    if (selection.isCollapsed) {
      final localOffset = getOffsetForCaret(selection.extent);
      final point =
          Offset(0.0, preferredLineHeight(selection.extent)) + localOffset;
      return TextSelectionPoint(point, null);
    }
    final boxes = getBoxesForSelection(selection);
    assert(boxes.isNotEmpty);
    return TextSelectionPoint(
        Offset(boxes.first.start, boxes.first.bottom), boxes.first.direction);
  }

  @override
  TextSelectionPoint getExtentEndpointForSelection(TextSelection selection) {
    if (selection.isCollapsed) {
      final localOffset = getOffsetForCaret(selection.extent);
      final point =
          Offset(0.0, preferredLineHeight(selection.extent)) + localOffset;
      return TextSelectionPoint(point, null);
    }
    final boxes = getBoxesForSelection(selection);
    assert(boxes.isNotEmpty);
    return TextSelectionPoint(
        Offset(boxes.last.end, boxes.last.bottom), boxes.last.direction);
  }

  @override
  List<TextBox> getBoxesForSelection(TextSelection selection) {
    final parentData = body!.parentData as BoxParentData;
    final boxes = body!.getBoxesForSelection(selection);
    return boxes.map((box) {
      return TextBox.fromLTRBD(
        box.left + parentData.offset.dx,
        box.top + parentData.offset.dy,
        box.right + parentData.offset.dx,
        box.bottom + parentData.offset.dy,
        box.direction,
      );
    }).toList(growable: false);
  }

  /// Marks the render object as needing to be laid out again and have its text
  /// metrics recomputed.
  ///
  /// Implies [markNeedsLayout].
  @protected
  void markNeedsTextLayout() => markNeedsLayout();

  // End RenderEditableBox implementation

  //

  // Start padding implementation

  /// The amount to pad the child in each dimension.
  ///
  /// If this is set to an [EdgeInsetsDirectional] object, then [textDirection]
  /// must not be null.
  EdgeInsetsGeometry get padding => _padding;
  EdgeInsetsGeometry _padding;

  set padding(EdgeInsetsGeometry value) {
    assert(value.isNonNegative);
    if (_padding == value) {
      return;
    }
    _padding = value;
    _markNeedsPaddingResolution();
  }

  EdgeInsets? _resolvedPadding;

  void _resolvePadding() {
    if (_resolvedPadding != null) {
      return;
    }
    _resolvedPadding = padding.resolve(textDirection);
    assert(_resolvedPadding!.isNonNegative);
  }

  void _markNeedsPaddingResolution() {
    _resolvedPadding = null;
    markNeedsLayout();
  }

  // End padding implementation

  //

  // Start cursor implementation

  CursorController _cursorController;

  set cursorController(CursorController value) {
    if (_cursorController == value) return;
    _cursorController = value;
    markNeedsLayout();
  }

  double get cursorWidth => _cursorController.style.width;

  double get cursorHeight =>
      _cursorController.style.height ??
      // hard code position to 0 here but it really doesn't matter since it's
      // the same for the entire paragraph of text.
      preferredLineHeight(const TextPosition(offset: 0));

  /// We cache containsCursor value because this method depends on the node
  /// state. In some cases the node gets detached from its document before this
  /// render object is detached from the render tree. This causes containsCursor
  /// to fail with an NPE when it's called from [detach].
  /// TODO: Investigate if this is still the case and [_containsCursor] is needed.
  bool _containsCursor = false;

  bool get containsCursor {
    if (node.parent == null) return _containsCursor;
    return _containsCursor = _cursorController.isFloatingCursorActive
        ? node.containsOffset(
            _cursorController.floatingCursorTextPosition.value!.offset)
        : selection.isCollapsed && node.containsOffset(selection.baseOffset);
  }

  late Rect _caretPrototype;

  // TODO(garyq): This is no longer producing the highest-fidelity caret
  // heights for Android, especially when non-alphabetic languages
  // are involved. The current implementation overrides the height set
  // here with the full measured height of the text on Android which looks
  // superior (subjectively and in terms of fidelity) in _paintCaret. We
  // should rework this properly to once again match the platform. The constant
  // _kCaretHeightOffset scales poorly for small font sizes.
  //
  /// On iOS, the cursor is taller than the cursor on Android. The height
  /// of the cursor for iOS is approximate and obtained through an eyeball
  /// comparison.
  void _computeCaretPrototype() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        _caretPrototype =
            Rect.fromLTWH(0.0, 0.0, cursorWidth, cursorHeight + 2);
        break;
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        _caretPrototype = Rect.fromLTWH(0.0, _kCursorHeightOffset, cursorWidth,
            cursorHeight - 2.0 * _kCursorHeightOffset);
        break;
    }
  }

  void _onFloatingCursorChange() {
    markNeedsPaint();
  }

  // End caret implementation

  //

  // Start render box overrides

  bool _attachedToCursorController = false;

  @override
  bool isRepaintBoundary = true;

  @override
  void attach(covariant PipelineOwner owner) {
    super.attach(owner);
    for (final child in _children) {
      child.attach(owner);
    }
    _cursorController.floatingCursorTextPosition
        .addListener(_onFloatingCursorChange);
    if (containsCursor) {
      _cursorController.addListener(markNeedsLayout);
      _cursorController.cursorColor.addListener(markNeedsPaint);
      _attachedToCursorController = true;
    }
  }

  @override
  void detach() {
    super.detach();
    for (final child in _children) {
      child.detach();
    }
    _cursorController.floatingCursorTextPosition
        .removeListener(_onFloatingCursorChange);
    if (_attachedToCursorController) {
      _cursorController.removeListener(markNeedsLayout);
      _cursorController.cursorColor.removeListener(markNeedsPaint);
      _attachedToCursorController = false;
    }
  }

  @override
  void redepthChildren() {
    _children.forEach(redepthChild);
  }

  @override
  void visitChildren(RenderObjectVisitor visitor) {
    _children.forEach(visitor);
  }

  @override
  List<DiagnosticsNode> debugDescribeChildren() {
    final value = <DiagnosticsNode>[];
    void add(RenderBox? child, String name) {
      if (child != null) {
        value.add(child.toDiagnosticsNode(name: name));
      }
    }

    add(leading, 'leading');
    add(body, 'body');
    return value;
  }

  @override
  bool get sizedByParent => false;

  @override
  double computeMinIntrinsicWidth(double height) {
    _resolvePadding();
    final horizontalPadding = _resolvedPadding!.left + _resolvedPadding!.right;
    final verticalPadding = _resolvedPadding!.top + _resolvedPadding!.bottom;
    final effectiveHeight = math.max(0.0, height - verticalPadding);
    final leadingWidth = leading?.getMinIntrinsicWidth(effectiveHeight) ?? 0;
    final bodyWidth = body?.getMinIntrinsicWidth(effectiveHeight) ?? 0;
    return horizontalPadding + leadingWidth + bodyWidth;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    _resolvePadding();
    final horizontalPadding = _resolvedPadding!.left + _resolvedPadding!.right;
    final verticalPadding = _resolvedPadding!.top + _resolvedPadding!.bottom;
    final effectiveHeight = math.max(0.0, height - verticalPadding);
    final leadingWidth = leading?.getMaxIntrinsicWidth(effectiveHeight) ?? 0;
    final bodyWidth = body?.getMaxIntrinsicWidth(effectiveHeight) ?? 0;
    return horizontalPadding + leadingWidth + bodyWidth;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    _resolvePadding();
    final horizontalPadding = _resolvedPadding!.left + _resolvedPadding!.right;
    final verticalPadding = _resolvedPadding!.top + _resolvedPadding!.bottom;
    if (body != null) {
      return body!
              .getMinIntrinsicHeight(math.max(0.0, width - horizontalPadding)) +
          verticalPadding;
    }
    return verticalPadding;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    _resolvePadding();
    final horizontalPadding = _resolvedPadding!.left + _resolvedPadding!.right;
    final verticalPadding = _resolvedPadding!.top + _resolvedPadding!.bottom;
    if (body != null) {
      return body!
              .getMaxIntrinsicHeight(math.max(0.0, width - horizontalPadding)) +
          verticalPadding;
    }
    return verticalPadding;
  }

  @override
  double computeDistanceToActualBaseline(TextBaseline baseline) {
    _resolvePadding();
    // The baseline of this widget is the baseline of the body.
    return body!.getDistanceToActualBaseline(baseline)! + _resolvedPadding!.top;
  }

  @override
  void performLayout() {
    final constraints = this.constraints;
    _selectionRects = null;

    _resolvePadding();
    assert(_resolvedPadding != null);

    if (body == null && leading == null) {
      size = constraints.constrain(Size(
        _resolvedPadding!.left + _resolvedPadding!.right,
        _resolvedPadding!.top + _resolvedPadding!.bottom,
      ));
      return;
    }
    final innerConstraints = constraints.deflate(_resolvedPadding!);

    final indentWidth = textDirection == TextDirection.ltr
        ? _resolvedPadding!.left
        : _resolvedPadding!.right;

    body!.layout(innerConstraints, parentUsesSize: true);
    final bodyParentData = body!.parentData as BoxParentData;
    bodyParentData.offset =
        Offset(_resolvedPadding!.left, _resolvedPadding!.top);

    if (leading != null) {
      final leadingConstraints = innerConstraints.copyWith(
          minWidth: indentWidth,
          maxWidth: indentWidth,
          maxHeight: body!.size.height);
      leading!.layout(leadingConstraints, parentUsesSize: true);
      final parentData = leading!.parentData as BoxParentData;
      final dxOffset =
          textDirection == TextDirection.rtl ? body!.size.width : 0.0;
      parentData.offset = Offset(dxOffset, _resolvedPadding!.top);
    }

    size = constraints.constrain(Size(
      _resolvedPadding!.left + body!.size.width + _resolvedPadding!.right,
      _resolvedPadding!.top + body!.size.height + _resolvedPadding!.bottom,
    ));

    _computeCaretPrototype();
  }

  CursorPainter get _cursorPainter => CursorPainter(
      editable: body!,
      style: _cursorController.style,
      cursorPrototype: _caretPrototype,
      effectiveColor: _cursorController.isFloatingCursorActive
          ? _cursorController.style.backgroundColor
          : _cursorController.cursorColor.value,
      devicePixelRatio: devicePixelRatio);

  @override
  void paint(PaintingContext context, Offset offset) {
    if (leading != null) {
      final parentData = leading!.parentData as BoxParentData;
      final effectiveOffset = offset + parentData.offset;
      context.paintChild(leading!, effectiveOffset);
    }

    if (body != null) {
      final parentData = body!.parentData as BoxParentData;
      final effectiveOffset = offset + parentData.offset;

      for (var item in node.children) {
        if (item is! TextNode) continue;
        _paintTextBackground(context, item, effectiveOffset);
      }

      if (_shouldPaintSelection && containsSelection) {
        final local = localSelection(node, selection);
        _selectionRects ??= body!.getBoxesForSelection(local);
        _paintSelection(context, effectiveOffset);
      }

      if (hasFocus &&
          _cursorController.showCursor.value &&
          containsCursor &&
          !_cursorController.style.paintAboveText) {
        _paintCursor(context, effectiveOffset);
      }

      context.paintChild(body!, effectiveOffset);

      if (hasFocus &&
          _cursorController.showCursor.value &&
          containsCursor &&
          _cursorController.style.paintAboveText) {
        _paintCursor(context, effectiveOffset);
      }
    }
  }

  // Paint line background if item is a TextNode and is inline code or has
  // a none transparent background color
  void _paintTextBackground(
      PaintingContext context, TextNode node, Offset effectiveOffset) {
    final isInlineCode = node.style.containsSame(ParchmentAttribute.inlineCode);
    final background = node.style.get(ParchmentAttribute.backgroundColor);
    if (!isInlineCode && background == null) return;

    Color? color;
    if (isInlineCode) {
      color = _inlineCodeTheme.backgroundColor;
    } else if (background?.value case final int value) {
      color = Color(value);
    }
    if (color == null || color == Colors.transparent) return;

    final textRange = TextSelection(
        baseOffset: node.offset, extentOffset: node.offset + node.length);
    final rects = body!.getBoxesForSelection(textRange);
    final paint = Paint()..color = color;

    for (final box in rects) {
      Rect rect = box.toRect().shift(effectiveOffset);
      if (isInlineCode) {
        rect = Rect.fromLTRB(
            rect.left - 2, rect.top + 1, rect.right + 2, rect.bottom + 1);
        if (_inlineCodeTheme.radius == null) {
          context.canvas.drawRect(rect, paint);
        } else {
          context.canvas.drawRRect(
              RRect.fromRectAndRadius(rect, _inlineCodeTheme.radius!), paint);
        }
      } else {
        context.canvas.drawRect(rect, paint);
      }
    }
  }

  void _paintSelection(PaintingContext context, Offset effectiveOffset) {
    assert(_selectionRects != null);
    final paint = Paint()..color = _selectionColor;
    for (final box in _selectionRects!) {
      context.canvas.drawRect(box.toRect().shift(effectiveOffset), paint);
    }
  }

  // Paints regular cursor OR the background cursor when floating cursor
  // is activated. The background cursor shows the closest text position of
  // the regular cursor corresponding to the current floating cursor
  // position should the latter be released
  // For painting of floating cursor, see RenderEditor::_paintFloatingCursor
  void _paintCursor(PaintingContext context, Offset effectiveOffset) {
    var textPosition = _cursorController.isFloatingCursorActive
        ? TextPosition(
            offset: _cursorController.floatingCursorTextPosition.value!.offset -
                node.documentOffset,
            affinity:
                _cursorController.floatingCursorTextPosition.value!.affinity)
        : TextPosition(
            offset: selection.extentOffset - node.documentOffset,
            affinity: selection.base.affinity);
    _cursorPainter.paint(context.canvas, effectiveOffset, textPosition);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (leading != null) {
      final childParentData = leading!.parentData as BoxParentData;
      final isHit = result.addWithPaintOffset(
        offset: childParentData.offset,
        position: position,
        hitTest: (result, transformed) =>
            leading!.hitTest(result, position: transformed),
      );
      if (isHit) return true;
    }
    if (body == null) return false;
    final parentData = body!.parentData as BoxParentData;
    final offset = position - parentData.offset;
    final textBoxes = body!.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: node.toPlainText().length));
    final isInTextBoxes = textBoxes.any((e) =>
        Rect.fromLTRB(e.left, e.top, e.right, e.bottom).contains(offset));
    if (isInTextBoxes) {
      return result.addWithPaintOffset(
        offset: parentData.offset,
        position: position,
        hitTest: (result, position) =>
            body!.hitTest(result, position: position),
      );
    }
    return false;
  }

// End render box overrides
}
