import 'package:flutter/widgets.dart';

/// Focus nodes made on demand for keyed widgets, such as one score box per
/// game, and freed once their widgets are no longer shown. Without the
/// freeing, a view that stays open all event keeps a node for every game
/// of every round ever posted.
class FocusNodePool {
  FocusNodePool(this._create);

  /// Makes the node for a key the first time it is asked for.
  final FocusNode Function(String key) _create;
  final _nodes = <String, FocusNode>{};

  /// The node for [key], if one has been made and not freed.
  FocusNode? operator [](String? key) => _nodes[key];

  /// The node for [key], made now if it does not exist.
  FocusNode node(String key) => _nodes.putIfAbsent(key, () => _create(key));

  /// The keys that have a node.
  Iterable<String> get keys => _nodes.keys;

  /// Whether any node has focus.
  bool get hasFocus => _nodes.values.any((node) => node.hasFocus);

  /// Whether any node has primary focus.
  bool get hasPrimaryFocus => _nodes.values.any((node) => node.hasPrimaryFocus);

  /// Frees every node whose key is not in [shown], the keys this build
  /// shows. Called while building: a freed node's Focus widget leaves the
  /// tree only as this frame lays out, so the node is disposed once the
  /// frame ends, and asking for its key meanwhile makes a fresh node.
  void retainOnly(Set<String> shown) {
    final stale = [
      for (final MapEntry(:key, :value) in _nodes.entries)
        if (!shown.contains(key)) value,
    ];
    if (stale.isEmpty) return;
    _nodes.removeWhere((key, _) => !shown.contains(key));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final node in stale) {
        node.dispose();
      }
    });
  }

  /// Disposes every node; the pool is not used afterwards.
  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    _nodes.clear();
  }
}
