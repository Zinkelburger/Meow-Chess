import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/us_chess.dart' show nameKey;

/// One choice in a [PlainSelect].
class SelectOption<T> {
  const SelectOption(this.value, this.label, {this.enabled = true});
  final T value;
  final String label;
  final bool enabled;
}

/// A desktop select: a labelled field whose list opens instantly directly
/// below it, at least as wide as the field, with a check beside the current
/// choice. The field itself stays visible, as with a native combo box.
///
/// Keyboard: Enter, Space, Alt+Down or Down opens it, on the current choice;
/// arrows move, skipping disabled choices; typing a letter jumps to the next
/// choice starting with it; Enter picks; Esc closes without changing anything.
class PlainSelect<T> extends StatefulWidget {
  const PlainSelect({
    required this.value,
    required this.options,
    required this.onChanged,
    this.label,
    this.hint,
    this.focusNode,
    this.dense = false,
    super.key,
  });

  /// The current choice. A value with no matching option shows [hint].
  final T value;
  final List<SelectOption<T>> options;

  /// Null disables the field.
  final ValueChanged<T>? onChanged;
  final String? label;

  /// Shown in the field while nothing is chosen.
  final String? hint;
  final FocusNode? focusNode;

  /// A borderless, compact field for table headers.
  final bool dense;

  @override
  State<PlainSelect<T>> createState() => _PlainSelectState<T>();
}

class _PlainSelectState<T> extends State<PlainSelect<T>> {
  final menu = MenuController();
  FocusNode? _ownFocus;
  FocusNode get focus => widget.focusNode ?? (_ownFocus ??= FocusNode());
  final itemFocus = <int, FocusNode>{};
  bool focused = false, hovered = false;

  bool get enabled => widget.onChanged != null;
  int get current => widget.options.indexWhere((o) => o.value == widget.value);

  @override
  void dispose() {
    _ownFocus?.dispose();
    for (final node in itemFocus.values) {
      node.dispose();
    }
    super.dispose();
  }

  void open() {
    if (!enabled) return;
    if (menu.isOpen) return menu.close();
    menu.open();
    // Start the keyboard on the current choice, as a native list does.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !menu.isOpen) return;
      final start = current >= 0 && widget.options[current].enabled
          ? current
          : widget.options.indexWhere((o) => o.enabled);
      if (start >= 0) reveal(start);
    });
  }

  /// Focuses a choice and scrolls the capped list to show it.
  void reveal(int index) {
    final node = itemFocus[index];
    if (node == null) return;
    node.requestFocus();
    if (node.context case final item? when item.mounted) {
      Scrollable.ensureVisible(item, alignment: 0.5);
    }
  }

  /// Typeahead: a letter moves to the next enabled choice that starts with it.
  KeyEventResult typeahead(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance;
    final typed = event.character?.trim() ?? '';
    if (typed.isEmpty ||
        keys.isControlPressed ||
        keys.isMetaPressed ||
        keys.isAltPressed) {
      return KeyEventResult.ignored;
    }
    final letter = nameKey(typed);
    final options = widget.options;
    final from =
        itemFocus.entries.where((e) => e.value.hasFocus).firstOrNull?.key ?? -1;
    for (var step = 1; step <= options.length; step++) {
      final i = (from + step) % options.length;
      if (options[i].enabled && nameKey(options[i].label).startsWith(letter)) {
        reveal(i);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void pick(T value) {
    menu.close();
    focus.requestFocus();
    if (value != widget.value) widget.onChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final chosen = current >= 0 ? widget.options[current] : null;
    final text = chosen?.label ?? widget.hint ?? '';
    final style = TextStyle(
      fontSize: 14,
      color: !enabled
          ? colors.onSurface.withValues(alpha: 0.38)
          : chosen == null
          ? colors.onSurfaceVariant
          : colors.onSurface,
    );
    final arrow = Icon(
      Icons.expand_more,
      size: 20,
      color: enabled
          ? colors.onSurfaceVariant
          : colors.onSurface.withValues(alpha: 0.38),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth ? constraints.maxWidth : 0.0;
        return MenuAnchor(
          controller: menu,
          childFocusNode: focus,
          consumeOutsideTap: true,
          onClose: () {
            if (mounted) setState(() {});
          },
          onOpen: () {
            if (mounted) setState(() {});
          },
          style: MenuStyle(
            minimumSize: WidgetStatePropertyAll(Size(width, 0)),
            maximumSize: WidgetStatePropertyAll(
              Size(math.max(width, 420), 360),
            ),
          ),
          menuChildren: [
            for (final (i, o) in widget.options.indexed)
              Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onKeyEvent: typeahead,
                child: MenuItemButton(
                  key: ValueKey(('select-option', i)),
                  focusNode: itemFocus.putIfAbsent(i, FocusNode.new),
                  closeOnActivate: false,
                  leadingIcon: SizedBox(
                    width: 18,
                    child: i == current
                        ? const Icon(Icons.check, size: 18)
                        : null,
                  ),
                  onPressed: o.enabled ? () => pick(o.value) : null,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: math.max(width, 420) - 64,
                    ),
                    child: Text(o.label, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ),
          ],
          builder: (context, controller, _) => Semantics(
            button: true,
            enabled: enabled,
            expanded: controller.isOpen,
            label: widget.label,
            value: text,
            excludeSemantics: true,
            child: FocusableActionDetector(
              focusNode: focus,
              enabled: enabled,
              mouseCursor: enabled
                  ? SystemMouseCursors.click
                  : MouseCursor.defer,
              onShowFocusHighlight: (v) => setState(() => focused = v),
              onShowHoverHighlight: (v) => setState(() => hovered = v),
              shortcuts: const {
                SingleActivator(LogicalKeyboardKey.arrowDown): ActivateIntent(),
                SingleActivator(LogicalKeyboardKey.arrowDown, alt: true):
                    ActivateIntent(),
                SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
                SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
                SingleActivator(LogicalKeyboardKey.numpadEnter):
                    ActivateIntent(),
              },
              actions: {
                ActivateIntent: CallbackAction<ActivateIntent>(
                  onInvoke: (_) => open(),
                ),
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: enabled
                    ? () {
                        focus.requestFocus();
                        open();
                      }
                    : null,
                child: widget.dense
                    ? Container(
                        height: 32,
                        padding: const EdgeInsets.only(left: 8, right: 4),
                        decoration: BoxDecoration(
                          color: hovered || controller.isOpen
                              ? colors.surfaceContainerHigh
                              : null,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: focused ? colors.onSurface : colors.outline,
                            width: focused ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                text,
                                style: style.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            arrow,
                          ],
                        ),
                      )
                    : InputDecorator(
                        isFocused: focused || controller.isOpen,
                        isHovering: hovered,
                        isEmpty: chosen == null && widget.hint == null,
                        decoration: InputDecoration(
                          labelText: widget.label,
                          enabled: enabled,
                          suffixIcon: arrow,
                          suffixIconConstraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 20,
                          ),
                        ),
                        child: Text(
                          text,
                          style: style,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}
