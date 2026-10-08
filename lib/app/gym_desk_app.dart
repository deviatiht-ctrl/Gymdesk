import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_strings.dart';
import 'providers.dart';
import 'router.dart';
import 'runtime.dart';
import 'theme.dart';

const appLocalizationDelegates = <LocalizationsDelegate<dynamic>>[
  AppStrings.delegate,
  _HaitianMaterialDelegate(),
  _HaitianCupertinoDelegate(),
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

class GymDeskApp extends ConsumerStatefulWidget {
  const GymDeskApp({super.key, this.passwordRecovery = false});
  final bool passwordRecovery;
  @override
  ConsumerState<GymDeskApp> createState() => _GymDeskAppState();
}

class _GymDeskAppState extends ConsumerState<GymDeskApp> {
  late final AppRuntime _runtime;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _runtime = ref.read(appRuntimeProvider);
    _router = createRouter(_runtime);
    unawaited(_runtime.initialize(passwordRecovery: widget.passwordRecovery));
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(appLanguageProvider);
    return ListenableBuilder(
      listenable: _runtime,
      builder: (context, _) => MaterialApp.router(
        title: 'GymDesk',
        debugShowCheckedModeBanner: false,
        routerConfig: _router,
        locale: locale,
        supportedLocales: AppStrings.locales,
        localizationsDelegates: appLocalizationDelegates,
        theme: gymTheme(_runtime.session?.gym?['accent_color'] as String?),
      ),
    );
  }
}

class _HaitianMaterialDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const _HaitianMaterialDelegate();
  @override
  bool isSupported(Locale locale) => locale.languageCode == 'ht';
  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      GlobalMaterialLocalizations.delegate.load(const Locale('fr'));
  @override
  bool shouldReload(_HaitianMaterialDelegate old) => false;
}

class _HaitianCupertinoDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const _HaitianCupertinoDelegate();
  @override
  bool isSupported(Locale locale) => locale.languageCode == 'ht';
  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      GlobalCupertinoLocalizations.delegate.load(const Locale('fr'));
  @override
  bool shouldReload(_HaitianCupertinoDelegate old) => false;
}
