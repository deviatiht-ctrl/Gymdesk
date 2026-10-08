import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_desk/app/gym_desk_app.dart';
import 'package:gym_desk/l10n/app_strings.dart';

void main() {
  test('Haitian Creole is supported alongside French and English', () {
    expect(AppStrings.locales.first.languageCode, 'ht');
    expect(const AppStrings(Locale('ht')).text('sign_in'), 'Konekte');
    expect(const AppStrings(Locale('fr')).text('sign_in'), 'Se connecter');
    expect(const AppStrings(Locale('en')).text('sign_in'), 'Sign in');
  });

  testWidgets('Material controls load for Haitian locale', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ht'),
        supportedLocales: AppStrings.locales,
        localizationsDelegates: appLocalizationDelegates,
        home: Builder(
          builder: (context) =>
              Scaffold(body: Text(AppStrings.of(context).text('sync'))),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Senkronizasyon'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
