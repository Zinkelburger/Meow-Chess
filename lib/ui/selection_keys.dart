import 'package:flutter/widgets.dart';

/// Keeps Up and Down working in text fields inside a [SelectionArea].
///
/// Flutter 3.47 throws on those keys there: a text field registers its
/// vertical caret action under [ExtendSelectionVerticallyToAdjacentLineIntent]
/// but typed for [DirectionalCaretMovementIntent], the selection area
/// overrides that intent, and its override casts the field's action to the
/// narrower type. The key is dropped and an error logged, in every field of
/// the workspace. Found by the UI fuzzer; see test/ui/selection_keys_test.dart.
///
/// Placed directly inside the [SelectionArea], this becomes the override
/// the field finds first. It hands a field's key back to the field, typed so
/// the framework's cast succeeds, and passes everything else to the
/// selection area above, so selecting text by keyboard is unchanged. Remove
/// it once Flutter no longer needs it (the test fails without it).
class TextFieldKeysInSelection extends StatelessWidget {
  const TextFieldKeysInSelection({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) => Actions(
    actions: {
      ExtendSelectionVerticallyToAdjacentLineIntent: _Vertical(context),
    },
    child: child,
  );
}

/// Typed as the text field types its own action, so [callingAction] casts.
class _Vertical extends ContextAction<DirectionalCaretMovementIntent> {
  _Vertical(this.outer);

  /// Above this widget's [Actions]: lookups from here reach the selection
  /// area's own action.
  final BuildContext outer;

  Action<Intent>? _region(Intent intent) =>
      Actions.maybeFind<Intent>(outer, intent: intent);

  @override
  bool isEnabled(
    DirectionalCaretMovementIntent intent, [
    BuildContext? context,
  ]) =>
      callingAction?.isEnabled(intent) ??
      (_region(intent)?.isEnabled(intent) ?? false);

  @override
  bool consumesKey(DirectionalCaretMovementIntent intent) =>
      callingAction?.consumesKey(intent) ??
      (_region(intent)?.consumesKey(intent) ?? false);

  @override
  Object? invoke(
    DirectionalCaretMovementIntent intent, [
    BuildContext? context,
  ]) {
    if (callingAction case final field?) return field.invoke(intent);
    return Actions.maybeInvoke(outer, intent);
  }
}
