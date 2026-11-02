import 'package:flutter/material.dart';

import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/focus_provider.dart';
import 'package:fladder/util/position_provider.dart';
import 'package:fladder/widgets/shared/ensure_visible.dart';
import 'package:fladder/widgets/shared/item_actions.dart';
import 'package:fladder/widgets/shared/modal_bottom_sheet.dart';

/// OX [EnumBox] fork: stays tappable with a single option so users can confirm
/// which file variant is selected.
class SushiEnumBox extends StatelessWidget {
  final String? current;
  final Widget? currentWidget;
  final bool autoFocus;
  /// Surface chip next to Trailer — must not match Play's primaryContainer.
  final bool secondary;
  final List<ItemAction> Function(BuildContext context) itemBuilder;
  final Function(bool focused)? onFocusChanged;

  const SushiEnumBox({
    this.current,
    this.currentWidget,
    this.autoFocus = false,
    this.secondary = false,
    required this.itemBuilder,
    this.onFocusChanged,
    super.key,
  }) : assert(
          current != null || currentWidget != null,
          "At least one of 'current' or 'currentWidget' must be provided",
        );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.titleMedium;
    const padding = EdgeInsets.symmetric(horizontal: 12, vertical: 6);
    final itemList = itemBuilder(context);
    final useBottomSheet = AdaptiveLayout.inputDeviceOf(context) != InputDevice.pointer;
    final foreGroundColor = secondary ? scheme.onSurface : scheme.onPrimaryContainer;
    final fillColor = secondary ? scheme.surfaceContainerLow : scheme.primaryContainer;
    final hasItems = itemList.isNotEmpty;
    final hasMultipleItems = itemList.length > 1;

    void openPicker() {
      if (!hasItems) return;
      showBottomSheetPill(
        context: context,
        content: (context, scrollController) => ListView(
          shrinkWrap: true,
          controller: scrollController,
          children: [
            const SizedBox(height: 6),
            ...itemList.map((e) => e.toListItem(context)),
          ],
        ),
      );
    }

    final labelWidget = Padding(
      padding: padding,
      child: Material(
        textStyle: textStyle?.copyWith(fontWeight: FontWeight.bold, color: foreGroundColor),
        color: Colors.transparent,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (currentWidget != null)
              DefaultTextStyle.merge(
                style: textStyle?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: foreGroundColor,
                ),
                child: currentWidget!,
              )
            else
              Text(current ?? '', textAlign: TextAlign.start),
            if (hasMultipleItems) ...[
              const SizedBox(width: 6),
              Icon(
                Icons.keyboard_arrow_down,
                color: foreGroundColor,
              ),
            ],
          ],
        ),
      ),
    );

    final position = PositionProvider.of(context);
    final borderRadius = BorderRadius.horizontal(
      left: position == null || position == PositionContext.first ? const Radius.circular(16) : const Radius.circular(4),
      right: position == null || position == PositionContext.last ? const Radius.circular(16) : const Radius.circular(4),
    );

    // No [Center] — that expands to maxWidth and breaks [Wrap] packing (one chip per line).
    return Container(
      decoration: BoxDecoration(
        color: fillColor.withAlpha(hasItems ? 255 : 100),
        borderRadius: borderRadius,
        border: BoxBorder.all(
          color: fillColor,
          strokeAlign: BorderSide.strokeAlignInside,
          width: 1,
        ),
      ),
      clipBehavior: Clip.hardEdge,
      child: useBottomSheet
          ? FocusButton(
              child: labelWidget,
              darkOverlay: false,
              autoFocus: autoFocus,
              borderRadius: borderRadius,
              onFocusChanged: onFocusChanged ??
                  (value) {
                    if (value) {
                      context.ensureVisible();
                    }
                  },
              onTap: hasItems ? openPicker : null,
            )
          : PopupMenuButton(
              tooltip: '',
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              enabled: hasItems,
              itemBuilder: (context) => itemList.map((e) => e.toPopupMenuItem()).toList(),
              padding: EdgeInsets.zero,
              child: labelWidget,
              requestFocus: true,
            ),
    );
  }
}
