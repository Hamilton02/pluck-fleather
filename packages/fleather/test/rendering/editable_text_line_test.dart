// ignore_for_file: use_full_hex_values_for_flutter_colors

import 'dart:ui';

import 'package:pluck_fleather/fleather.dart';
import 'package:pluck_fleather/src/rendering/editable_text_line.dart';
import 'package:pluck_fleather/src/rendering/paragraph_proxy.dart';
import 'package:pluck_fleather/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pluck_parchment/parchment.dart';

import 'rendering_tools.dart';

void main() {
  late final CursorController cursorController;

  setUpAll(() {
    cursorController = CursorController(
      showCursor: ValueNotifier(false),
      style:
          const CursorStyle(color: Colors.blue, backgroundColor: Colors.blue),
      tickerProvider: FakeTickerProvider(),
    );
    TestRenderingFlutterBinding.ensureInitialized();
  });

  group('$RenderEditableTextLine', () {
    test('Correctly computes containsCursor if node is updated', () {
      final lineNode = LineNode()..insert(0, 'some text', null);
      final rootNode = RootNode();
      rootNode.addFirst(lineNode);
      final renderBox = RenderEditableTextLine(
          node: lineNode,
          padding: EdgeInsets.zero,
          textDirection: TextDirection.ltr,
          cursorController: cursorController,
          selection: const TextSelection.collapsed(offset: 6),
          selectionColor: Colors.blue,
          enableInteractiveSelection: false,
          hasFocus: false,
          inlineCodeTheme: InlineCodeThemeData(style: const TextStyle()));
      layout(renderBox, constraints: const BoxConstraints(maxWidth: 100));
      expect(renderBox.containsCursor, equals(true));
      lineNode.delete(4, 5);
      expect(renderBox.containsCursor, equals(false));
    });

    test('Correctly computes containsCursor if node is detached', () {
      final lineNode = LineNode()..insert(0, 'some text', null);
      final renderBox = RenderEditableTextLine(
          node: lineNode,
          padding: EdgeInsets.zero,
          textDirection: TextDirection.ltr,
          cursorController: cursorController,
          selection: const TextSelection.collapsed(offset: 6),
          selectionColor: Colors.blue,
          enableInteractiveSelection: false,
          hasFocus: false,
          inlineCodeTheme: InlineCodeThemeData(style: const TextStyle()));
      layout(renderBox, constraints: const BoxConstraints(maxWidth: 100));
      expect(renderBox.containsCursor, equals(false));
    });

    test('Does not hit test body when tap is outside of text boxes', () {
      final lineNode = LineNode();
      final rootNode = RootNode();
      rootNode.addFirst(lineNode);
      final renderBox = RenderEditableTextLine(
          node: lineNode,
          padding: EdgeInsets.zero,
          textDirection: TextDirection.ltr,
          cursorController: cursorController,
          selection: const TextSelection.collapsed(offset: 0),
          selectionColor: Colors.blue,
          enableInteractiveSelection: false,
          hasFocus: false,
          inlineCodeTheme: InlineCodeThemeData(style: const TextStyle()));
      renderBox.body = RenderParagraphProxy(
          textStyle: const TextStyle(),
          textScaler: TextScaler.noScaling,
          child: RenderParagraph(
            const TextSpan(
                text: 'A text with that will be broken into multiple lines'),
            textDirection: TextDirection.ltr,
          ),
          textDirection: TextDirection.ltr,
          textWidthBasis: TextWidthBasis.parent);
      layout(renderBox, constraints: const BoxConstraints(maxWidth: 100));
      expect(
          renderBox.hitTestChildren(BoxHitTestResult(),
              position: const Offset(10, 2)),
          equals(true));
      expect(
          renderBox.hitTestChildren(BoxHitTestResult(),
              position: const Offset(80, 100)),
          equals(false));
    });

    test('Background color', () {
      final lineNode = LineNode()
        ..insert(0, 'some text', ParchmentStyle.fromJson({'bg': 0xffff0000}));
      final rootNode = RootNode();
      rootNode.addFirst(lineNode);
      final paintingContext = MockPaintingContext();
      final renderParagraph = RenderParagraph(const TextSpan(text: 'some text'),
          textDirection: TextDirection.ltr);
      final renderBox = RenderEditableTextLine(
          node: lineNode,
          padding: EdgeInsets.zero,
          textDirection: TextDirection.ltr,
          cursorController: cursorController,
          selection: const TextSelection.collapsed(offset: 0),
          selectionColor: Colors.blue,
          enableInteractiveSelection: false,
          hasFocus: false,
          inlineCodeTheme: InlineCodeThemeData(style: const TextStyle()));
      renderBox.body = RenderParagraphProxy(
          child: renderParagraph,
          textStyle: const TextStyle(),
          textScaler: TextScaler.noScaling,
          textDirection: TextDirection.ltr,
          textWidthBasis: TextWidthBasis.parent);
      layout(renderBox);
      renderBox.paint(paintingContext, Offset.zero);
      expect(paintingContext.canvas.drawnRect, isNotNull);
      expect(paintingContext.canvas.drawnRect!.width, greaterThan(100));
      expect(paintingContext.canvas.drawnRect!.height, greaterThan(10));
      expect(paintingContext.canvas.drawnRectPaint!.style, PaintingStyle.fill);
      expect(paintingContext.canvas.drawnRectPaint!.color,
          const Color(0xffff0000));
    });

    test('inline code', () {
      final lineNode = LineNode()
        ..insert(0, 'some text', ParchmentStyle.fromJson({'c': true}));
      final rootNode = RootNode();
      rootNode.addFirst(lineNode);
      final paintingContext = MockPaintingContext();
      final renderParagraph = RenderParagraph(const TextSpan(text: 'some text'),
          textDirection: TextDirection.ltr);
      final renderBox = RenderEditableTextLine(
          node: lineNode,
          padding: EdgeInsets.zero,
          textDirection: TextDirection.ltr,
          cursorController: cursorController,
          selection: const TextSelection.collapsed(offset: 0),
          selectionColor: Colors.blue,
          enableInteractiveSelection: false,
          hasFocus: false,
          inlineCodeTheme: InlineCodeThemeData(
              style: const TextStyle(),
              backgroundColor: const Color(0xffff00000)));
      renderBox.body = RenderParagraphProxy(
          child: renderParagraph,
          textStyle: const TextStyle(),
          textScaler: TextScaler.noScaling,
          textDirection: TextDirection.ltr,
          textWidthBasis: TextWidthBasis.parent);
      layout(renderBox);
      renderBox.paint(paintingContext, Offset.zero);
      expect(paintingContext.canvas.drawnRect, isNotNull);
      expect(paintingContext.canvas.drawnRect!.width, greaterThan(100));
      expect(paintingContext.canvas.drawnRect!.height, greaterThan(10));
      expect(paintingContext.canvas.drawnRectPaint!.style, PaintingStyle.fill);
      expect(paintingContext.canvas.drawnRectPaint!.color.value32Bits,
          const Color(0xffff00000).value32Bits);
    });
  });
}

class FakeTickerProvider extends Fake implements TickerProvider {
  @override
  Ticker createTicker(TickerCallback onTick) => FakeTicker();
}

class FakeTicker extends Fake implements Ticker {
  @override
  String toString({bool debugIncludeStack = false}) {
    return super.toString();
  }
}

class MockCanvas extends Fake implements Canvas {
  Rect? drawnRect;
  Paint? drawnRectPaint;

  @override
  void drawRect(Rect rect, Paint paint) {
    drawnRect = rect;
    drawnRectPaint = paint;
  }

  @override
  void drawParagraph(Paragraph paragraph, Offset offset) {}
}

class MockPaintingContext extends Fake implements PaintingContext {
  @override
  final MockCanvas canvas = MockCanvas();

  @override
  void paintChild(RenderObject child, Offset offset) {
    child.paint(this, offset);
  }
}
