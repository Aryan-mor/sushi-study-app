import 'package:flutter/material.dart';

import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';

/// Always a [Wrap] so a long action list flows onto the next line instead of overflowing.
/// On a TV the enclosing [FocusRow] still traverses every child in reading order with the
/// d-pad; [alignment] only takes effect on touch/desktop where the group can be centered.
class SushiDetailActionLayout extends StatelessWidget {
  final WrapAlignment alignment;
  final List<Widget> children;

  const SushiDetailActionLayout({
    required this.alignment,
    required this.children,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final isDPad = AdaptiveLayout.inputDeviceOf(context) == InputDevice.dPad;

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      alignment: isDPad ? WrapAlignment.start : alignment,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }
}
