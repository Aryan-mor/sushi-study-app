import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Riverpod smoke: ProviderScope builds', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Text('sushi-test'),
          ),
        ),
      ),
    );
    expect(find.text('sushi-test'), findsOneWidget);
  });
}
