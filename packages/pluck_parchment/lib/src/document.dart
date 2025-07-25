import 'dart:async';

import 'package:parchment_delta/parchment_delta.dart';

import 'document/attributes.dart';
import 'document/block.dart';
import 'document/embeds.dart';
import 'document/line.dart';
import 'document/node.dart';
import 'heuristics.dart';

/// Source of a [ParchmentChange].
enum ChangeSource {
  /// Change originated from a local action. Typically triggered by user.
  local,

  /// Change originated from a remote action.
  remote,

  /// Change originated from undo/redo action
  history,
}

/// Represents a change in a [ParchmentDocument].
class ParchmentChange {
  ParchmentChange(this.before, this.change, this.source);

  /// Document state before [change].
  final Delta before;

  /// Change delta applied to the document.
  final Delta change;

  /// The source of this change.
  final ChangeSource source;
}

/// A rich text document.
class ParchmentDocument {
  /// Creates new empty Parchment document.
  ParchmentDocument(
      {ParchmentHeuristics heuristics = ParchmentHeuristics.fallback})
      : _heuristics = heuristics,
        _delta = Delta()..insert('\n') {
    _loadDocument(_delta);
  }

  /// Creates new ParchmentDocument from provided JSON `data`.
  ParchmentDocument.fromJson(List data,
      {ParchmentHeuristics heuristics = ParchmentHeuristics.fallback})
      : _heuristics = heuristics,
        _delta = _migrateDelta(Delta.fromJson(data)) {
    _loadDocument(_delta);
  }

  /// Creates new ParchmentDocument from provided `delta`.
  ParchmentDocument.fromDelta(Delta delta,
      {ParchmentHeuristics heuristics = ParchmentHeuristics.fallback})
      : _heuristics = heuristics,
        _delta = _migrateDelta(delta) {
    _loadDocument(_delta);
  }

  /// Creates new ParchmentDocument from provided JSON `data`.
  ParchmentDocument.fromMarkdown(String markdown,
      {ParchmentHeuristics heuristics = ParchmentHeuristics.fallback})
      : _heuristics = heuristics,
        _delta = _migrateDelta(Delta.fromJson(markdownToDelta(markdown))) {
    _loadDocument(_delta);
  }

  final ParchmentHeuristics _heuristics;

  /// The root node of this document tree.
  RootNode get root => _root;
  final RootNode _root = RootNode();

  /// Length of this document.
  int get length => _root.length;

  /// Stream of [ParchmentChange]s applied to this document.
  Stream<ParchmentChange> get changes => _controller.stream;

  final StreamController<ParchmentChange> _controller =
      StreamController.broadcast();

  /// Returns contents of this document as [Delta].
  Delta toDelta() => Delta.from(_delta);
  Delta _delta;

  /// Returns plain text representation of this document.
  String toPlainText() => _root.children.map((e) => e.toPlainText()).join('');

  dynamic toJson() {
    return _delta.toJson();
  }

  /// Returns `true` if this document and associated stream of [changes]
  /// is closed.
  ///
  /// Modifying a closed document is not allowed.
  bool get isClosed => _controller.isClosed;

  /// Closes [changes] stream.
  void close() {
    _controller.close();
  }

  /// Inserts [data] in this document at specified [index].
  ///
  /// The `data` parameter can be either a String or an instance of
  /// [EmbeddableObject].
  ///
  /// Applies heuristic rules before modifying this document and
  /// produces a change event with its source set to [ChangeSource.local].
  ///
  /// Returns an instance of [Delta] actually composed into this document.
  Delta insert(int index, Object data) {
    assert(index >= 0);
    if (data is String) {
      if (data.isEmpty) return Delta();
    } else {
      assert(data is EmbeddableObject);
      data = (data as EmbeddableObject).toJson();
    }

    final change = _heuristics.applyInsertRules(this, index, data);
    compose(change, ChangeSource.local);
    return change;
  }

  /// Deletes [length] of characters from this document starting at [index].
  ///
  /// This method applies heuristic rules before modifying this document and
  /// produces a [ParchmentChange] with source set to [ChangeSource.local].
  ///
  /// Returns an instance of [Delta] actually composed into this document.
  Delta delete(int index, int length) {
    assert(index >= 0 && length > 0);
    final change = _heuristics.applyDeleteRules(this, index, length);
    if (change.isNotEmpty) {
      // Delete rules are allowed to prevent the edit so it may be empty.
      compose(change, ChangeSource.local);
    }
    return change;
  }

  /// Replaces [length] of characters starting at [index] with [data].
  ///
  /// This method applies heuristic rules before modifying this document and
  /// produces a change event with its source set to [ChangeSource.local].
  ///
  /// Returns an instance of [Delta] actually composed into this document.
  Delta replace(int index, int length, Object data) {
    assert(data is String || data is EmbeddableObject);

    final dataIsNotEmpty = (data is String) ? data.isNotEmpty : true;

    assert(index >= 0 && (dataIsNotEmpty || length > 0),
        'With index $index, length $length and text "$data"');

    var delta = Delta();

    // We have to insert before applying delete rules
    // Otherwise delete would be operating on stale document snapshot.
    if (dataIsNotEmpty) {
      delta = insert(index + length, data);
    }

    if (length > 0) {
      final deleteDelta = delete(index, length);
      delta = delta.compose(deleteDelta);
    }

    return delta;
  }

  /// Formats segment of this document with specified [attribute].
  ///
  /// Applies heuristic rules before modifying this document and
  /// produces a change event with its source set to [ChangeSource.local].
  ///
  /// Returns an instance of [Delta] actually composed into this document.
  /// The returned [Delta] may be empty in which case this document remains
  /// unchanged and no change event is published to the [changes] stream.
  Delta format(int index, int length, ParchmentAttribute attribute) {
    assert(index >= 0 && length >= 0);

    var change = Delta();

    final formatChange =
        _heuristics.applyFormatRules(this, index, length, attribute);
    if (formatChange.isNotEmpty) {
      compose(formatChange, ChangeSource.local);
      change = change.compose(formatChange);
    }

    return change;
  }

  /// Returns style of specified text range.
  ///
  /// Only attributes applied to all characters within this range are
  /// included in the result. Inline and block level attributes are
  /// handled separately, e.g.:
  ///
  /// - block attribute X is included in the result only if it exists for
  ///   every line within this range (partially included lines are counted).
  /// - inline attribute X is included in the result only if it exists
  ///   for every character within this range (line-break characters excluded).
  ParchmentStyle collectStyle(int index, int length) {
    var result = lookupLine(index);
    var line = result.node as LineNode;
    return line.collectStyle(result.offset, length);
  }

  /// Returns [LineNode] located at specified character [offset].
  LookupResult lookupLine(int offset) {
    // TODO: prevent user from moving caret after last line-break.
    var result = _root.lookup(offset, inclusive: true);
    if (result.node is LineNode) return result;
    var block = result.node as BlockNode;
    return block.lookup(result.offset, inclusive: true);
  }

  /// Composes [change] Delta into this document.
  ///
  /// Use this method with caution as it does not apply heuristic rules to the
  /// [change].
  ///
  /// It is callers responsibility to ensure that the [change] conforms to
  /// the document model semantics and can be composed with the current state
  /// of this document.
  ///
  /// In case the [change] is invalid, behavior of this method is unspecified.
  void compose(Delta change, ChangeSource source) {
    _checkMutable();
    change.trim();
    assert(change.isNotEmpty);

    var offset = 0;
    final before = toDelta();
    change = _migrateDelta(change);
    for (final op in change.toList()) {
      final attributes =
          op.attributes != null ? ParchmentStyle.fromJson(op.attributes) : null;
      if (op.isInsert) {
        // Must normalize data before inserting into the document, makes sure
        // that any embedded objects are converted into EmbeddableObject type.
        final data = _normalizeData(op.data);
        _root.insert(offset, data, attributes);
      } else if (op.isDelete) {
        _root.delete(offset, op.length);
      } else if (op.attributes != null) {
        _root.retain(offset, op.length, attributes);
      }
      if (!op.isDelete) offset += op.length;
    }
    _delta = _delta.compose(change);

    if (_delta != _root.toDelta()) {
      throw StateError('Compose produced inconsistent results. '
          'This is likely due to a bug in the library. Tried to compose change $change from $source.');
    }
    _controller.add(ParchmentChange(before, change, source));
  }

  //
  // Overridden members
  //
  @override
  String toString() => _root.toString();

  //
  // Private members
  //

  void _checkMutable() {
    assert(!_controller.isClosed,
        'Cannot modify Parchment document after it was closed.');
  }

  /// Key of the embed attribute used in Parchment 0.x (prior to 1.0).
  static const String _kEmbedAttributeKey = 'embed';

  /// Migrates `delta` to the latest format supported by Parchment documents.
  ///
  /// Allows backward compatibility with 0.x versions of Parchment package.
  static Delta _migrateDelta(Delta delta) {
    final result = Delta();
    for (final op in delta.toList()) {
      if (op.hasAttribute(_kEmbedAttributeKey)) {
        // Convert legacy embed style attribute into the embed insert operation.
        final attrs = Map<String, dynamic>.from(op.attributes!);
        final data = Map<String, dynamic>.from(attrs[_kEmbedAttributeKey]);
        data[EmbeddableObject.kTypeKey] = data['type'];
        data[EmbeddableObject.kInlineKey] = false;
        data.remove('type');
        final embed = EmbeddableObject.fromJson(data);
        attrs.remove(_kEmbedAttributeKey);
        result.push(Operation.insert(embed, attrs.isNotEmpty ? attrs : null));
      } else {
        result.push(op);
      }
    }
    return result;
  }

  Object _normalizeData(Object data) {
    return data is String
        ? data
        : data is EmbeddableObject
            ? data
            : EmbeddableObject.fromJson(data as Map<String, dynamic>);
  }

  /// Loads [document] delta into this document.
  void _loadDocument(Delta doc) {
    assert((doc.last.data as String).endsWith('\n'),
        'Invalid document delta. Document delta must always end with a line-break.');
    var offset = 0;
    for (final op in doc.toList()) {
      final style =
          op.attributes != null ? ParchmentStyle.fromJson(op.attributes) : null;
      if (op.isInsert) {
        final data = _normalizeData(op.data);
        _root.insert(offset, data, style);
      } else {
        throw ArgumentError.value(doc,
            'Document Delta can only contain insert operations but ${op.key} found.');
      }
      offset += op.length;
    }
    // Must remove last line if it's empty and with no styles.
    // TODO: find a way for DocumentRoot to not create extra line when composing initial delta.
    final node = _root.last;
    if (node is LineNode &&
        node.parent is! BlockNode &&
        node.style.isEmpty &&
        _root.childCount > 1) {
      _root.remove(node);
    }
  }

  static List<Map<String, dynamic>> markdownToDelta(String markdown) {
    final lines = markdown.split(RegExp(r'\r?\n'));
    final ops = <Map<String, dynamic>>[];

    List<Map<String, dynamic>> inlinePatterns = [
      {
        'regex': RegExp(r'\*\*(.+?)\*\*'),
        'attr': {'bold': true},
      },
      {
        'regex': RegExp(r'__(.+?)__'),
        'attr': {'bold': true},
      },
      {
        'regex': RegExp(r'\*(.+?)\*'),
        'attr': {'italic': true},
      },
      {
        'regex': RegExp(r'_(.+?)_'),
        'attr': {'italic': true},
      },
      {
        'regex': RegExp(r'~~(.+?)~~'),
        'attr': {'strike': true},
      },
      {
        'regex': RegExp(r'`(.+?)`'),
        'attr': {'code': true},
      },
      {
        'regex': RegExp(r'\[([^\]]+)\]\(([^)]+)\)'),
        'attr': (Match m) => {'link': m.group(2)},
      },
    ];

    List<Map<String, dynamic>> parseInline(String text,
        [Map<String, dynamic>? inherited]) {
      for (var pattern in inlinePatterns) {
        final regex = pattern['regex'] as RegExp;
        final match = regex.firstMatch(text);
        if (match != null) {
          final before = text.substring(0, match.start);
          final content = match.group(1)!;
          final after = text.substring(match.end);
          final attr = pattern['attr'] is Function
              ? pattern['attr'](match)
              : Map<String, dynamic>.from(pattern['attr']);

          final newAttrs = Map<String, dynamic>.from(inherited ?? {});
          newAttrs.addAll(attr);

          return [
            ...parseInline(before, inherited),
            ...parseInline(content, newAttrs),
            ...parseInline(after, inherited)
          ];
        }
      }

      if (text.isEmpty) return [];
      final op = <String, dynamic>{'insert': text};
      if (inherited != null && inherited.isNotEmpty) {
        op['attributes'] = inherited;
      }
      return [op];
    }

    int i = 0;
    while (i < lines.length) {
      final line = lines[i];

      // Fenced code block
      if (line.startsWith('```')) {
        final language = line.substring(3).trim();
        i++;
        final buffer = StringBuffer();
        while (i < lines.length && !lines[i].startsWith('```')) {
          buffer.writeln(lines[i]);
          i++;
        }
        i++; // Skip closing ```
        ops.add({
          'insert': buffer.toString(),
          'attributes': {
            'code-block': true,
            if (language.isNotEmpty) 'language': language
          }
        });
        continue;
      }

      // Blockquote
      if (line.startsWith('>')) {
        final buffer = StringBuffer();
        while (i < lines.length && lines[i].startsWith('>')) {
          final quoteLine = lines[i].replaceFirst(RegExp(r'^>\s?'), '');
          buffer.writeln(quoteLine);
          i++;
        }
        final block = buffer.toString().trimRight();
        ops.addAll(parseInline(block));
        ops.add({
          'insert': '\n',
          'attributes': {'blockquote': true}
        });
        continue;
      }

      // Header
      final headerMatch = RegExp(r'^(#{1,6})\s+(.*)').firstMatch(line);
      if (headerMatch != null) {
        final level = headerMatch.group(1)!.length;
        final content = headerMatch.group(2)!;
        ops.addAll(parseInline(content));
        ops.add({
          'insert': '\n',
          'attributes': {'header': level}
        });
        i++;
        continue;
      }

      // Unordered list
      final ulMatch = RegExp(r'^[-*+]\s+(.*)').firstMatch(line);
      if (ulMatch != null) {
        ops.addAll(parseInline(ulMatch.group(1)!));
        ops.add({
          'insert': '\n',
          'attributes': {'list': 'bullet'}
        });
        i++;
        continue;
      }

      // Ordered list
      final olMatch = RegExp(r'^\d+\.\s+(.*)').firstMatch(line);
      if (olMatch != null) {
        ops.addAll(parseInline(olMatch.group(1)!));
        ops.add({
          'insert': '\n',
          'attributes': {'list': 'ordered'}
        });
        i++;
        continue;
      }

      // Blank line
      if (line.trim().isEmpty) {
        ops.add({'insert': '\n'});
        i++;
        continue;
      }

      // Paragraph
      ops.addAll(parseInline(line));
      ops.add({'insert': '\n'});
      i++;
    }

    return ops;
  }
}
