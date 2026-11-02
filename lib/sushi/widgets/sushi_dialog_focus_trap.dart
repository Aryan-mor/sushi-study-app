import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keeps D-pad / remote focus inside a modal for as long as it is open.
///
/// Home poster rows call [FocusNode.requestFocus] after layout (see
/// `horizontal_list.dart` / [FocusButton]). That bypasses the modal route and
/// moves primary focus to the screen behind the dialog. Checking
/// [FocusScopeNode.hasFocus] is not enough — this trap:
/// 1. Detects when [FocusManager.primaryFocus] is outside the dialog
/// 2. Disables that foreign [FocusScopeNode] so later `requestFocus` calls no-op
/// 3. Moves focus back onto the dialog action
///
/// On dismiss the reverse must happen in that same turn: unlock first, then
/// give primary focus back. Otherwise TV has no focused widget (the route
/// restore already failed against a locked scope) and D-pad keys go nowhere
/// until a force-close.
class SushiDialogFocusTrap extends StatefulWidget {
  const SushiDialogFocusTrap({
    required this.child,
    this.primaryFocus,
    super.key,
  });

  final Widget child;
  final FocusNode? primaryFocus;

  static int _active = 0;

  /// True while an [SushiDialogFocusTrap] is in the tree.
  static bool get isActive => _active > 0;

  @override
  State<SushiDialogFocusTrap> createState() => _SushiDialogFocusTrapState();
}

class _SushiDialogFocusTrapState extends State<SushiDialogFocusTrap> {
  Timer? _poll;
  bool _ensuring = false;
  bool _closing = false;
  FocusNode? _restoreFocus;
  final _locked = <FocusScopeNode, ({bool canRequest, bool descendants})>{};

  @override
  void initState() {
    super.initState();
    SushiDialogFocusTrap._active++;
    FocusManager.instance.addListener(_ensure);
    HardwareKeyboard.instance.addHandler(_onKey);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensure());
    _poll = Timer.periodic(const Duration(milliseconds: 80), (_) => _ensure());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    FocusScope.of(context).traversalEdgeBehavior =
        TraversalEdgeBehavior.closedLoop;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      _beginClose();
    }
  }

  bool _onKey(KeyEvent event) {
    _ensure();
    return false;
  }

  bool _owns(FocusNode? node) {
    if (node == null) return false;
    if (identical(node, widget.primaryFocus)) return true;
    final ctx = node.context;
    if (ctx == null) return false;
    return ctx.findAncestorStateOfType<_SushiDialogFocusTrapState>() == this;
  }

  bool _scopeContainsUs(FocusScopeNode scope) {
    final ours = FocusScope.of(context);
    return identical(scope, ours) || ours.ancestors.contains(scope);
  }

  void _ensure() {
    if (_closing || !mounted || _ensuring) return;
    _ensuring = true;
    try {
      if (_closing || !mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) {
        _beginClose();
        return;
      }
      final primary = FocusManager.instance.primaryFocus;
      if (_owns(primary)) return;

      if (primary != null) {
        _lockForeignScope(primary);
      }
      if (_closing) return;
      _focusSelf();
    } finally {
      _ensuring = false;
      if (_closing) {
        _unlock();
      }
    }
  }

  void _lockForeignScope(FocusNode thief) {
    if (_closing) return;
    final scope = thief.enclosingScope;
    if (scope == null) return;
    if (identical(scope, FocusManager.instance.rootScope)) return;
    if (_scopeContainsUs(scope)) return;

    _restoreFocus = thief;
    if (_locked.containsKey(scope)) return;

    _locked[scope] = (
      canRequest: scope.canRequestFocus,
      descendants: scope.descendantsAreFocusable,
    );
    scope.canRequestFocus = false;
    scope.descendantsAreFocusable = false;
  }

  void _focusSelf() {
    if (_closing) return;
    final node = widget.primaryFocus;
    if (node != null && node.canRequestFocus) {
      node.requestFocus();
      return;
    }
    if (!mounted) return;
    final scope = FocusScope.of(context);
    for (final child in scope.traversalDescendants) {
      if (child.canRequestFocus && child.context != null && _owns(child)) {
        child.requestFocus();
        return;
      }
    }
  }

  void _unlock() {
    for (final entry in _locked.entries) {
      try {
        entry.key.canRequestFocus = entry.value.canRequest;
        entry.key.descendantsAreFocusable = entry.value.descendants;
      } catch (_) {}
    }
    _locked.clear();
  }

  void _restoreFocusSoon(FocusNode? preferred) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (preferred != null && preferred.canRequestFocus && preferred.context != null) {
        preferred.requestFocus();
        return;
      }
      final primary = FocusManager.instance.primaryFocus;
      if (primary != null &&
          primary.canRequestFocus &&
          primary.context != null &&
          !identical(primary, FocusManager.instance.rootScope)) {
        return;
      }
      for (final node in FocusManager.instance.rootScope.traversalDescendants) {
        if (node.canRequestFocus && node.context != null) {
          node.requestFocus();
          return;
        }
      }
    });
  }

  void _beginClose() {
    if (_closing) return;
    _closing = true;
    _poll?.cancel();
    HardwareKeyboard.instance.removeHandler(_onKey);
    FocusManager.instance.removeListener(_ensure);
    final preferred = _restoreFocus;
    _restoreFocus = null;
    _unlock();
    _restoreFocusSoon(preferred);
  }

  @override
  void dispose() {
    _beginClose();
    SushiDialogFocusTrap._active--;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      policy: WidgetOrderTraversalPolicy(),
      child: widget.child,
    );
  }
}
