import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/sushi/widgets/sushi_dialog_focus_trap.dart';

void main() {
  testWidgets('Later dismiss restores D-pad focus to the screen behind the trap', (tester) async {
    final homeFocus = FocusNode(debugLabel: 'home-poster');
    addTearDown(homeFocus.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              FilledButton(
                focusNode: homeFocus,
                autofocus: true,
                onPressed: () {},
                child: const Text('Poster'),
              ),
              FilledButton(
                onPressed: () {},
                child: const Text('Next'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(homeFocus.hasPrimaryFocus, isTrue);

    final openContext = tester.element(find.byType(Scaffold));
    showDialog<void>(
      context: openContext,
      barrierDismissible: false,
      builder: (ctx) => SushiDialogFocusTrap(
        child: AlertDialog(
          title: const Text('Update available'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Not now'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Later'),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Later'), findsOneWidget);
    expect(homeFocus.hasPrimaryFocus, isFalse);

    homeFocus.requestFocus();
    await tester.pump(const Duration(milliseconds: 100));
    expect(homeFocus.hasPrimaryFocus, isFalse, reason: 'trap must keep D-pad inside the dialog');

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();

    expect(find.text('Later'), findsNothing);
    expect(homeFocus.enclosingScope?.canRequestFocus, isTrue);
    expect(homeFocus.enclosingScope?.descendantsAreFocusable, isTrue);
    expect(
      homeFocus.hasPrimaryFocus,
      isTrue,
      reason: 'TV D-pad is dead unless a widget behind the dialog takes primary focus',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(Focus.of(tester.element(find.text('Next'))).hasPrimaryFocus, isTrue);
  });

  testWidgets('Not now dismiss also unlocks the screen behind the trap', (tester) async {
    final homeFocus = FocusNode(debugLabel: 'home-poster');
    addTearDown(homeFocus.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return FilledButton(
                focusNode: homeFocus,
                autofocus: true,
                onPressed: () {},
                child: const Text('Poster'),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    showDialog<void>(
      context: tester.element(find.byType(Scaffold)),
      barrierDismissible: false,
      builder: (ctx) => SushiDialogFocusTrap(
        child: AlertDialog(
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    homeFocus.requestFocus();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(homeFocus.enclosingScope?.descendantsAreFocusable, isTrue);
    expect(homeFocus.hasPrimaryFocus, isTrue);
  });
}
