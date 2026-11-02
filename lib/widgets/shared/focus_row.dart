import 'package:flutter/material.dart';

import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/widgets/navigation_scaffold/components/navigation_body.dart';
import 'package:fladder/widgets/navigation_scaffold/components/side_navigation_bar.dart';
import 'package:fladder/widgets/shared/ensure_visible.dart';

/// Currently-mounted [FocusRow] group nodes, used to resolve vertical d-pad navigation between
/// independent rows stacked in a scrollable column (e.g. the dashboard's slider -> list -> list
/// layout). Flutter's built-in directional focus search operates on individual leaf nodes across
/// the whole [FocusScope] and picks by rect overlap/distance; since each row (e.g. a
/// [HorizontalList]) scrolls independently, a focused item deep in one row often has no
/// horizontal overlap with the row directly above/below it, so that search can skip over the
/// adjacent row entirely and land somewhere further away (e.g. jumping straight to a top banner).
/// Up/down at a row's edge is resolved by stepping to the nearest *registered* row purely by
/// vertical position first, instead of falling straight through to that generic search.
final Set<FocusNode> _activeRowGroups = <FocusNode>{};

/// Last vertical d-pad hop. [ensureVisible] uses this so UP does not center the
/// already-visible row above (that slide looks like scrolling down).
TraversalDirection? lastVerticalTraversal;

/// Alignment for the last vertical hop. UP keeps the row near the top; DOWN
/// keeps current center-ish behaviour so the new row and its info stay in view.
double tvVerticalScrollAlignment() {
  return switch (lastVerticalTraversal) {
    TraversalDirection.up => 0.2,
    TraversalDirection.down => 0.55,
    _ => 0.5,
  };
}

/// UP: do not yank a visible upper row to the center. DOWN: pin newly revealed
/// rows at the end so they enter from below.
ScrollPositionAlignmentPolicy tvVerticalScrollPolicy() {
  return switch (lastVerticalTraversal) {
    TraversalDirection.up => ScrollPositionAlignmentPolicy.keepVisibleAtStart,
    TraversalDirection.down => ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    _ => ScrollPositionAlignmentPolicy.explicit,
  };
}

/// The nearest other registered row group strictly above/below [current] in [direction], scoped
/// to the same [FocusScopeNode] (so rows on a different, offstage page are never candidates), or
/// null if there isn't one (or [direction] isn't vertical).
FocusNode? adjacentRowGroup(FocusNode current, TraversalDirection direction) {
  if (direction != TraversalDirection.up && direction != TraversalDirection.down) return null;
  if (current.context?.mounted != true) return null;
  final currentTop = current.rect.top;
  final scope = current.nearestScope;

  FocusNode? best;
  double? bestTop;
  for (final candidate in _activeRowGroups) {
    if (identical(candidate, current)) continue;
    if (candidate.context?.mounted != true) continue;
    if (candidate.nearestScope != scope) continue;
    final top = candidate.rect.top;
    if (direction == TraversalDirection.up) {
      if (top >= currentTop) continue;
      if (bestTop == null || top > bestTop) {
        best = candidate;
        bestTop = top;
      }
    } else {
      if (top <= currentTop) continue;
      if (bestTop == null || top < bestTop) {
        best = candidate;
        bestTop = top;
      }
    }
  }
  return best;
}

class FocusRow extends StatefulWidget {
  final Widget child;

  /// Null = pick alignment from [lastVerticalTraversal] so UP/DOWN scroll the
  /// matching way. Pass an explicit value to lock a page (e.g. details = 1.0).
  final double? ensureVisibleAlignment;
  final FocusNode? focusNode;
  final WidgetOrderTraversalPolicy? traversalPolicy;
  final bool escapeToNavBar;
  final void Function(FocusNode groupNode)? onGroupFocused;
  final void Function(bool hasFocus)? onFocusChange;

  const FocusRow({
    required this.child,
    this.ensureVisibleAlignment,
    this.focusNode,
    this.traversalPolicy,
    this.onGroupFocused,
    this.onFocusChange,
    this.escapeToNavBar = true,
    super.key,
  });

  @override
  State<FocusRow> createState() => _FocusRowState();
}

class _FocusRowState extends State<FocusRow> {
  late FocusNode _groupNode;
  FocusNode? _lastChild;

  /// The child focus was on when a vertical hop left this group. [_lastChild] is cleared on that
  /// hop (a row is re-entered from its start), but a multi-line group re-entered from below should
  /// land back on its bottom line — this remembers which item that was.
  FocusNode? _verticalExitChild;

  /// Last primary focus outside this group — i.e. where focus came from when the group is entered.
  FocusNode? _lastOutsideFocus;

  bool _clearedByVertical = false;

  bool get _ownsNode => widget.focusNode == null;

  late final VoidCallback _focusManagerListener;

  @override
  void initState() {
    super.initState();
    _groupNode = widget.focusNode ?? FocusNode();
    _activeRowGroups.add(_groupNode);

    _focusManagerListener = _handleFocusManagerChange;
    FocusManager.instance.addListener(_focusManagerListener);
  }

  @override
  void dispose() {
    _activeRowGroups.remove(_groupNode);
    FocusManager.instance.removeListener(_focusManagerListener);
    if (_ownsNode) _groupNode.dispose();
    super.dispose();
  }

  void _handleFocusManagerChange() {
    final f = FocusManager.instance.primaryFocus;
    if (f != null && f != _groupNode && _groupNode.descendants.contains(f)) {
      _lastChild = f;
    } else if (f != null && f != _groupNode) {
      _lastOutsideFocus = f;
    }
  }

  void _clearOnVertical() {
    _verticalExitChild = _lastChild;
    _lastChild = null;
    _clearedByVertical = true;
  }

  void _focusFirstChild() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final nodes = _childNodes(_groupNode);
      if (nodes.isEmpty) return;

      if (widget.onGroupFocused != null) {
        widget.onGroupFocused!(_groupNode);
        return;
      }

      FocusNode target;
      final rows = _visualRows(nodes);
      final exitChild = _verticalExitChild;

      // Decided by where focus actually came from, not by [lastVerticalTraversal]: that global is
      // only written by FocusRow/HorizontalList hops, so after leaving this group UPWARDS through
      // Flutter's generic search it stays `up`, and the next DOWN into the group was mistaken for
      // an entry from below and yanked to the bottom line next to Cast.
      final from = _lastOutsideFocus;
      final enteredFromBelow =
          from != null && from.context?.mounted == true && from.rect.top >= _groupNode.rect.bottom - 1;

      if (enteredFromBelow && rows.length > 1) {
        // Entered from below: continue from the bottom line, not jump back to the first item.
        target = exitChild != null && rows.last.contains(exitChild) ? exitChild : rows.last.first;
        _lastChild = target;
      } else if (_lastChild != null &&
          !_clearedByVertical &&
          _lastChild!.canRequestFocus &&
          _lastChild!.context?.mounted == true) {
        target = _lastChild!;
      } else {
        target = nodes.first;
        _lastChild = target;
      }

      target.requestFocus();
      try {
        final alignment = widget.ensureVisibleAlignment;
        target.context?.ensureVisible(
          alignment: alignment ?? tvVerticalScrollAlignment(),
          alignmentPolicy: alignment == null
              ? tvVerticalScrollPolicy()
              : ScrollPositionAlignmentPolicy.explicit,
        );
      } catch (_) {}

      _clearedByVertical = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      policy: widget.traversalPolicy ??
          _RowFocusPolicy(
            groupNode: _groupNode,
            onVertical: _clearOnVertical,
            escapeToNavBar: widget.escapeToNavBar,
          ),
      child: Focus(
        focusNode: _groupNode,
        skipTraversal: true,
        onFocusChange: (value) {
          widget.onFocusChange?.call(value);
          if (value && AdaptiveLayout.inputDeviceOf(context) == InputDevice.dPad) {
            _focusFirstChild();
          }
        },
        child: widget.child,
      ),
    );
  }
}

/// Row-major order: group nodes into visual rows (tops within [_rowTolerance]px), then
/// left-to-right within each row. For a single row this is identical to a pure horizontal
/// sort, so a [Row] is unaffected; a [Wrap] that spills onto a second line still traverses
/// predictably with a d-pad (finish row 1, then row 2) instead of zig-zagging by x only.
const double _rowTolerance = 24;

int _readingOrderCompare(FocusNode a, FocusNode b) {
  final dy = a.rect.top - b.rect.top;
  if (dy.abs() > _rowTolerance) return dy < 0 ? -1 : 1;
  return a.rect.left.compareTo(b.rect.left);
}

List<FocusNode> _childNodes(FocusNode node) {
  final all = node.descendants.where((n) => n.canRequestFocus && n.context != null && !n.skipTraversal).toList();
  return all.where((n) => !all.any((other) => other != n && n.descendants.contains(other))).toList()
    ..sort(_readingOrderCompare);
}

List<List<FocusNode>> _visualRows(List<FocusNode> nodes) {
  final rows = <List<FocusNode>>[];
  for (final node in nodes) {
    if (rows.isEmpty || (node.rect.top - rows.last.first.rect.top).abs() > _rowTolerance) {
      rows.add([node]);
    } else {
      rows.last.add(node);
    }
  }
  return rows;
}

FocusNode? _nodeOnAdjacentRow(FocusNode groupNode, FocusNode current, TraversalDirection direction) {
  if (direction != TraversalDirection.up && direction != TraversalDirection.down) return null;
  final leaves = _childNodes(groupNode);
  FocusNode? resolved = leaves.contains(current) ? current : null;
  if (resolved == null) {
    for (final leaf in leaves) {
      if (leaf.ancestors.contains(current) || current.ancestors.contains(leaf)) {
        resolved = leaf;
        break;
      }
    }
  }
  if (resolved == null) return null;
  final rows = _visualRows(leaves);
  var rowIndex = -1;
  var colIndex = -1;
  for (var r = 0; r < rows.length; r++) {
    final c = rows[r].indexOf(resolved);
    if (c != -1) {
      rowIndex = r;
      colIndex = c;
      break;
    }
  }
  if (rowIndex == -1) return null;
  final nextRowIndex = direction == TraversalDirection.down ? rowIndex + 1 : rowIndex - 1;
  if (nextRowIndex < 0 || nextRowIndex >= rows.length) return null;
  final row = rows[nextRowIndex];
  return row[colIndex.clamp(0, row.length - 1)];
}

class _RowFocusPolicy extends WidgetOrderTraversalPolicy {
  final VoidCallback? onVertical;
  final FocusNode groupNode;
  final bool escapeToNavBar;

  _RowFocusPolicy({this.onVertical, required this.groupNode, required this.escapeToNavBar});

  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    final isRtl = Directionality.of(currentNode.context!) == TextDirection.rtl;
    final towardsSidebar = isRtl ? TraversalDirection.right : TraversalDirection.left;
    final parent = currentNode.parent;
    final nodes = parent == null
        ? <FocusNode>[]
        : parent.descendants
            .where((n) => n.canRequestFocus && n.context != null && !n.skipTraversal)
            .toList()
      ..sort(_readingOrderCompare);

    if (nodes.isEmpty) return super.inDirection(currentNode, direction);
    final index = nodes.indexOf(currentNode);
    if (index == -1) return super.inDirection(currentNode, direction);

    switch (direction) {
      case TraversalDirection.left:
        if (index > 0) {
          nodes[index - 1].requestFocus();
        } else if (direction == towardsSidebar) {
          lastMainFocus = currentNode;
          if (navBarNode.canRequestFocus && navBarNode.context?.mounted == true && escapeToNavBar) {
            final cb = FocusTraversalPolicy.defaultTraversalRequestFocusCallback;
            cb(navBarNode);
          }
        }
        return true;
      case TraversalDirection.right:
        if (index < nodes.length - 1) {
          nodes[index + 1].requestFocus();
        } else if (direction == towardsSidebar) {
          lastMainFocus = currentNode;
          if (navBarNode.canRequestFocus && navBarNode.context?.mounted == true && escapeToNavBar) {
            final cb = FocusTraversalPolicy.defaultTraversalRequestFocusCallback;
            cb(navBarNode);
          }
        }
        return true;
      case TraversalDirection.up:
      case TraversalDirection.down:
        lastVerticalTraversal = direction;
        onVertical?.call();
        // Stay inside a Wrap's next/previous visual row first, then step to the nearest
        // registered sibling row (e.g. the next FocusRow up/down the page). Escape via
        // [super.inDirection] from the *current* button rect only as a last resort — never by
        // focusing the parent FocusScope (full-screen rect has nothing below).
        final inGroup = _nodeOnAdjacentRow(groupNode, currentNode, direction);
        if (inGroup != null) {
          // Not a bare requestFocus(): a multi-line group (e.g. the season episode grid) is taller
          // than the screen, and nothing else scrolls the next line into view.
          // Explicit alignment rather than keepVisibleAtEnd: the latter parks the focused line on
          // the bottom edge, cutting off the title label under each poster.
          FocusTraversalPolicy.defaultTraversalRequestFocusCallback(
            inGroup,
            alignment: tvVerticalScrollAlignment(),
            alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
          );
          return true;
        }
        final adjacentGroup = adjacentRowGroup(groupNode, direction);
        if (adjacentGroup != null) {
          final cb = FocusTraversalPolicy.defaultTraversalRequestFocusCallback;
          cb(adjacentGroup);
          return true;
        }
        return super.inDirection(currentNode, direction);
    }
  }
}
