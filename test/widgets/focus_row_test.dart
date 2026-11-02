import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/screens/home_screen.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout_model.dart';
import 'package:fladder/util/poster_defaults.dart';
import 'package:fladder/widgets/shared/focus_row.dart';

Widget _tvHost({required Widget child}) {
  return MaterialApp(
    home: AdaptiveLayout(
      data: const AdaptiveLayoutModel(
        viewSize: ViewSize.television,
        layoutMode: LayoutMode.dual,
        inputDevice: InputDevice.dPad,
        platform: TargetPlatform.android,
        isDesktop: false,
        posterDefaults: PosterDefaults(size: 350, ratio: 0.55),
        controller: <HomeTabs, ScrollController>{},
        sideBarWidth: 80,
        topBarHeight: 0,
      ),
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('d-pad down leaves FocusRow for the widget below', (tester) async {
    await tester.pumpWidget(
      _tvHost(
        child: Column(
          children: [
            FocusRow(
              child: FilledButton(
                autofocus: true,
                onPressed: () {},
                child: const Text('Play'),
              ),
            ),
            const SizedBox(height: 48),
            FilledButton(
              onPressed: () {},
              child: const Text('Episodes'),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(Focus.of(tester.element(find.text('Play'))).hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(
      Focus.of(tester.element(find.text('Episodes'))).hasPrimaryFocus,
      isTrue,
      reason: 'down from the action row must reach content below',
    );
  });

  testWidgets('d-pad down inside a Wrap moves to the next visual row first', (tester) async {
    await tester.pumpWidget(
      _tvHost(
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 220,
            child: FocusRow(
              child: Wrap(
                spacing: 8,
                runSpacing: 24,
                children: [
                  for (final label in ['Play', 'Audio', 'Follow', 'More'])
                    SizedBox(
                      width: 100,
                      height: 40,
                      child: FilledButton(
                        autofocus: label == 'Play',
                        onPressed: () {},
                        child: Text(label),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(Focus.of(tester.element(find.text('Play'))).hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(Focus.of(tester.element(find.text('Follow'))).hasPrimaryFocus, isTrue);
  });

  testWidgets('d-pad up moves to the FocusRow above, not the first on the page', (tester) async {
    lastVerticalTraversal = null;
    await tester.pumpWidget(
      _tvHost(
        child: Column(
          children: [
            FocusRow(
              child: FilledButton(
                onPressed: () {},
                child: const Text('Banner'),
              ),
            ),
            const SizedBox(height: 48),
            FocusRow(
              child: FilledButton(
                onPressed: () {},
                child: const Text('Continue'),
              ),
            ),
            const SizedBox(height: 48),
            FocusRow(
              child: FilledButton(
                autofocus: true,
                onPressed: () {},
                child: const Text('Trending'),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(Focus.of(tester.element(find.text('Trending'))).hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();

    expect(
      Focus.of(tester.element(find.text('Continue'))).hasPrimaryFocus,
      isTrue,
      reason: 'up from a rail must land on the adjacent row, not the top banner',
    );
    expect(lastVerticalTraversal, TraversalDirection.up);
  });

  testWidgets('d-pad up does not increase scroll offset (no down-slide)', (tester) async {
    lastVerticalTraversal = null;
    final controller = ScrollController();
    await tester.pumpWidget(
      _tvHost(
        child: SizedBox(
          height: 220,
          child: ListView(
            controller: controller,
            children: [
              SizedBox(
                height: 140,
                child: FocusRow(
                  child: FilledButton(
                    onPressed: () {},
                    child: const Text('Upper'),
                  ),
                ),
              ),
              SizedBox(
                height: 140,
                child: FocusRow(
                  child: FilledButton(
                    autofocus: true,
                    onPressed: () {},
                    child: const Text('Lower'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(Focus.of(tester.element(find.text('Lower'))).hasPrimaryFocus, isTrue);
    final offsetBefore = controller.offset;

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();

    expect(Focus.of(tester.element(find.text('Upper'))).hasPrimaryFocus, isTrue);
    expect(
      controller.offset,
      lessThanOrEqualTo(offsetBefore + 0.5),
      reason: 'UP must not scroll the upper row downward (center-align looks like down)',
    );
  });

  test('tvVerticalScrollPolicy maps UP to keepVisibleAtStart', () {
    lastVerticalTraversal = TraversalDirection.up;
    expect(tvVerticalScrollPolicy(), ScrollPositionAlignmentPolicy.keepVisibleAtStart);
    expect(tvVerticalScrollAlignment(), 0.2);

    lastVerticalTraversal = TraversalDirection.down;
    expect(tvVerticalScrollPolicy(), ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
    expect(tvVerticalScrollAlignment(), 0.55);

    lastVerticalTraversal = null;
    expect(tvVerticalScrollPolicy(), ScrollPositionAlignmentPolicy.explicit);
    expect(tvVerticalScrollAlignment(), 0.5);
  });
}
