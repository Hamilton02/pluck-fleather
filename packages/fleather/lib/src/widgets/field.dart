import 'package:flutter/material.dart';
import 'package:pluck_parchment/parchment.dart';

import '../services/clipboard_manager.dart';
import 'controller.dart';
import 'editor.dart';

class FleatherField extends StatefulWidget {
  /// Controller object which establishes a link between a rich text document
  /// and this editor.
  ///
  /// Must not be null.
  final FleatherController controller;

  /// Controls whether this editor has keyboard focus.
  ///
  /// Can be `null` in which case this editor creates its own instance to
  /// control keyboard focus.
  final FocusNode? focusNode;

  /// The [ScrollController] to use when vertically scrolling the contents.
  ///
  /// If `null` then this editor instantiates a new ScrollController.
  ///
  /// Scroll controller must not be `null` if [scrollable] is set to `false`.
  final ScrollController? scrollController;

  /// Whether this editor should create a scrollable container for its content.
  ///
  /// When set to `true` the editor's height can be controlled by [minHeight],
  /// [maxHeight] and [expands] properties.
  ///
  /// When set to `false` the editor always expands to fit the entire content
  /// of the document and should normally be placed as a child of another
  /// scrollable widget, otherwise the content may be clipped.
  ///
  /// The [scrollController] property must not be `null` when this is set to
  /// `false`.
  ///
  /// Set to `true` by default.
  final bool scrollable;

  /// Additional space around the content of this editor.
  final EdgeInsetsGeometry padding;

  /// Whether this editor should focus itself if nothing else is already
  /// focused.
  ///
  /// If true, the keyboard will open as soon as this editor obtains focus.
  /// Otherwise, the keyboard is only shown after the user taps the editor.
  ///
  /// Defaults to `false`. Cannot be `null`.
  final bool autofocus;

  /// Whether to show cursor.
  ///
  /// The cursor refers to the blinking caret when the editor is focused.
  final bool showCursor;

  /// Whether the text can be changed.
  ///
  /// When this is set to `true`, the text cannot be modified
  /// by any shortcut or keyboard operation. The text is still selectable.
  ///
  /// Defaults to `false`. Must not be `null`.
  final bool readOnly;

  /// Whether to enable autocorrection.
  ///
  /// Defaults to `true`.
  final bool autocorrect;

  /// Whether to show input suggestions as the user types.
  ///
  /// This flag only affects Android. On iOS, suggestions are tied directly to
  /// [autocorrect], so that suggestions are only shown when [autocorrect] is
  /// true. On Android autocorrection and suggestion are controlled separately.
  ///
  /// Defaults to true.
  final bool enableSuggestions;

  /// Whether to enable user interface affordances for changing the
  /// text selection.
  ///
  /// For example, setting this to true will enable features such as
  /// long-pressing the editor to select text and show the
  /// cut/copy/paste menu, and tapping to move the text cursor.
  ///
  /// When this is false, the text selection cannot be adjusted by
  /// the user, text cannot be copied, and the user cannot paste into
  /// the text field from the clipboard.
  final bool enableInteractiveSelection;

  /// The minimum height to be occupied by this editor.
  ///
  /// This only has effect if [scrollable] is set to `true` and [expands] is
  /// set to `false`.
  final double? minHeight;

  /// The maximum height to be occupied by this editor.
  ///
  /// This only has effect if [scrollable] is set to `true` and [expands] is
  /// set to `false`.
  final double? maxHeight;

  /// Whether this editor's height will be sized to fill its parent.
  ///
  /// This only has effect if [scrollable] is set to `true`.
  ///
  /// If expands is set to true and wrapped in a parent widget like [Expanded]
  /// or [SizedBox], the editor will expand to fill the parent.
  ///
  /// [maxHeight] and [minHeight] must both be `null` when this is set to
  /// `true`.
  ///
  /// Defaults to `false`.
  final bool expands;

  /// Configures how the platform keyboard will select an uppercase or
  /// lowercase keyboard.
  ///
  /// Only supports text keyboards, other keyboard types will ignore this
  /// configuration. Capitalization is locale-aware.
  ///
  /// Defaults to [TextCapitalization.sentences]. Must not be `null`.
  final TextCapitalization textCapitalization;

  /// The appearance of the keyboard.
  ///
  /// This setting is only honored on iOS devices.
  ///
  /// Defaults to [ThemeData.brightness].
  final Brightness? keyboardAppearance;

  /// The [ScrollPhysics] to use when vertically scrolling the input.
  ///
  /// This only has effect if [scrollable] is set to `true`.
  ///
  /// If not specified, it will behave according to the current platform.
  ///
  /// See [Scrollable.physics].
  final ScrollPhysics? scrollPhysics;

  /// Callback to invoke when user wants to launch a URL.
  final ValueChanged<String?>? onLaunchUrl;

  final InputDecoration? decoration;

  final Widget? toolbar;

  /// Configuration that details how spell check should be performed.
  ///
  /// Specifies the [SpellCheckService] used to spell check text input and the
  /// [TextStyle] used to style text with misspelled words.
  ///
  /// If the [SpellCheckService] is left null, spell check is disabled by
  /// default unless the [DefaultSpellCheckService] is supported, in which case
  /// it is used. It is currently supported only on Android and iOS.
  ///
  /// If this configuration is left null, then spell check is disabled by default.
  final SpellCheckConfiguration? spellCheckConfiguration;

  /// Builder function for embeddable objects.
  ///
  /// Defaults to [defaultFleatherEmbedBuilder].
  final FleatherEmbedBuilder embedBuilder;

  /// Builds the text selection toolbar when requested by the user.
  ///
  /// Defaults to [defaultContextMenuBuilder].
  final FleatherContextMenuBuilder contextMenuBuilder;

  /// Provides clipboard status and getter and setter for clipboard data
  /// for paste, copy and cut functionality.
  ///
  /// Defaults to [PlainTextClipboardManager]
  final ClipboardManager clipboardManager;

  final GlobalKey<EditorState>? editorKey;

  const FleatherField({
    super.key,
    required this.controller,
    this.editorKey,
    this.focusNode,
    this.scrollController,
    this.scrollable = true,
    this.padding = EdgeInsets.zero,
    this.autofocus = false,
    this.showCursor = true,
    this.readOnly = false,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.enableInteractiveSelection = true,
    this.minHeight,
    this.maxHeight,
    this.expands = false,
    this.textCapitalization = TextCapitalization.sentences,
    this.keyboardAppearance,
    this.scrollPhysics,
    this.onLaunchUrl,
    this.decoration,
    this.toolbar,
    this.contextMenuBuilder = defaultContextMenuBuilder,
    this.spellCheckConfiguration,
    this.embedBuilder = defaultFleatherEmbedBuilder,
    this.clipboardManager = const PlainTextClipboardManager(),
  });

  @override
  State<FleatherField> createState() => _FleatherFieldState();
}

class _FleatherFieldState extends State<FleatherField> {
  late bool _focused;

  FocusNode? _internalFocusNode;

  FocusNode get effectiveFocusNode =>
      widget.focusNode ?? (_internalFocusNode ??= FocusNode());

  void _editorFocusChanged() {
    setState(() {
      _focused = effectiveFocusNode.hasFocus;
    });
  }

  @override
  void initState() {
    super.initState();
    _focused = effectiveFocusNode.hasFocus;
    effectiveFocusNode.addListener(_editorFocusChanged);
  }

  @override
  void didUpdateWidget(covariant FleatherField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      oldWidget.focusNode?.removeListener(_editorFocusChanged);
      if (widget.focusNode != null) {
        _internalFocusNode?.dispose();
        _internalFocusNode = null;
      }
      effectiveFocusNode.addListener(_editorFocusChanged);
      _focused = effectiveFocusNode.hasFocus;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keyboardAppearance = widget.keyboardAppearance ?? theme.brightness;

    Widget child = FleatherEditor(
      controller: widget.controller,
      editorKey: widget.editorKey,
      focusNode: effectiveFocusNode,
      scrollController: widget.scrollController,
      scrollable: widget.scrollable,
      padding: widget.padding,
      autofocus: widget.autofocus,
      showCursor: widget.showCursor,
      readOnly: widget.readOnly,
      autocorrect: widget.autocorrect,
      enableSuggestions: widget.enableSuggestions,
      enableInteractiveSelection: widget.enableInteractiveSelection,
      minHeight: widget.minHeight,
      maxHeight: widget.maxHeight,
      expands: widget.expands,
      textCapitalization: widget.textCapitalization,
      keyboardAppearance: keyboardAppearance,
      scrollPhysics: widget.scrollPhysics,
      onLaunchUrl: widget.onLaunchUrl,
      embedBuilder: widget.embedBuilder,
      spellCheckConfiguration: widget.spellCheckConfiguration,
      contextMenuBuilder: widget.contextMenuBuilder,
      clipboardManager: widget.clipboardManager,
    );

    if (widget.toolbar != null) {
      child = Column(
        children: [
          child,
          Visibility(
            visible: _focused,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: widget.toolbar!,
          ),
        ],
      );
    }

    return AnimatedBuilder(
      animation: Listenable.merge(
          <Listenable?>[effectiveFocusNode, widget.controller]),
      builder: (BuildContext context, Widget? child) {
        return InputDecorator(
          decoration: _getEffectiveDecoration(),
          isFocused: effectiveFocusNode.hasFocus,
          isEmpty: _isEmpty,
          child: child,
        );
      },
      child: child,
    );
  }

  /// Field is considered empty when the document consists of
  /// a single empty line of text with no styles applied to it
  bool get _isEmpty {
    if (widget.controller.document.length > 1) {
      return false;
    }
    final node = widget.controller.document.root.first;
    assert(node is StyledNode);
    return (node as StyledNode).style.isEmpty;
  }

  InputDecoration _getEffectiveDecoration() {
    final effectiveDecoration = (widget.decoration ?? const InputDecoration())
        .applyDefaults(Theme.of(context).inputDecorationTheme)
        .copyWith(
          enabled: !widget.readOnly,
          hintMaxLines: widget.decoration?.hintMaxLines,
        );

    return effectiveDecoration;
  }
}
