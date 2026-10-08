import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'app/env.dart';
import 'app/gym_desk_app.dart';
import 'app/theme.dart';
import 'core/auth/secure_session_storage.dart';
import 'core/widgets/async_panel.dart';
import 'l10n/app_strings.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  runApp(const ProviderScope(child: _Bootstrap()));
}

class _Bootstrap extends StatefulWidget {
  const _Bootstrap();
  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  late Future<void> _ready;
  bool _passwordRecovery = false;
  String? _initialRecoveryToken;

  @override
  void initState() {
    super.initState();
    try {
      final parameters = Uri.splitQueryString(Uri.base.fragment);
      if (parameters['type'] == 'recovery') {
        _initialRecoveryToken = parameters['access_token'];
      }
    } on FormatException {
      _initialRecoveryToken = null;
    }
    _ready = _initialize();
  }

  Future<void> _initialize() async {
    if (!AppEnv.configured) return;
    await Supabase.initialize(
      url: AppEnv.supabaseUrl,
      publishableKey: AppEnv.supabaseKey,
      debug: false,
      authOptions: FlutterAuthClientOptions(
        localStorage: SecureSessionStorage(Uri.parse(AppEnv.supabaseUrl).host),
      ),
    );
    _passwordRecovery =
        _initialRecoveryToken != null &&
        _initialRecoveryToken ==
            Supabase.instance.client.auth.currentSession?.accessToken;
    _initialRecoveryToken = null;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _ready,
    builder: (context, snapshot) {
      if (AppEnv.configured &&
          snapshot.connectionState == ConnectionState.done &&
          !snapshot.hasError) {
        return GymDeskApp(passwordRecovery: _passwordRecovery);
      }
      return MaterialApp(
        title: 'GymDesk',
        debugShowCheckedModeBanner: false,
        theme: gymTheme(null),
        locale: const Locale('ht'),
        supportedLocales: AppStrings.locales,
        localizationsDelegates: appLocalizationDelegates,
        home: Builder(
          builder: (context) {
            final s = AppStrings.of(context);
            return Scaffold(
              body: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: !AppEnv.configured
                          ? MessagePanel(
                              message:
                                  '${s.text('configuration')}\n\n${s.text('configuration_hint')}',
                            )
                          : snapshot.hasError
                          ? MessagePanel(
                              message: s.text('error'),
                              action: s.text('retry'),
                              onAction: () =>
                                  setState(() => _ready = _initialize()),
                            )
                          : const LoadingPanel(),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    },
  );
}
