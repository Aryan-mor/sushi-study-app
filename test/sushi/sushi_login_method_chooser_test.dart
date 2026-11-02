import 'package:fladder/sushi/sushi_login_method_chooser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap({required Locale locale, required bool sideBySide}) {
    return MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('fa')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: SingleChildScrollView(
          child: SushiLoginMethodChooser(
            sideBySide: sideBySide,
            onPhone: _noop,
            onBot: _noop,
          ),
        ),
      ),
    );
  }

  testWidgets('chooser stacks on phone', (tester) async {
    await tester.pumpWidget(wrap(locale: const Locale('en'), sideBySide: false));

    final split = tester.widget<Column>(find.byKey(const Key('login-method-split')));
    expect(split.children.length, 3);
    expect(find.text('Easy sign-in with your phone'), findsOneWidget);
    expect(find.textContaining('First time takes two steps'), findsOneWidget);
  });

  testWidgets('chooser is side-by-side on tablet and Persian copy', (tester) async {
    await tester.pumpWidget(wrap(locale: const Locale('fa'), sideBySide: true));

    expect(find.byKey(const Key('login-method-split')), findsOneWidget);
    expect(tester.widget(find.byKey(const Key('login-method-split'))), isA<Row>());
    expect(find.text('ورود آسان با شماره موبایل'), findsOneWidget);
    expect(find.textContaining('فقط بار اول دو مرحله‌ست'), findsOneWidget);
  });
}

void _noop() {}
