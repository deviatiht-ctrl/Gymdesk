import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/access_control/access_popup_overlay.dart';
import '../core/sync/sync_models.dart';
import '../core/widgets/async_panel.dart';
import '../features/admin/presentation/declarations_page.dart';
import '../features/admin/presentation/email_settings_page.dart';
import '../features/admin/presentation/offers_page.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/auth/presentation/password_reset_page.dart';
import '../features/auth/presentation/signup_page.dart';
import '../features/auth/presentation/unlock_page.dart';
import '../features/attendance/presentation/kiosk_page.dart';
import '../features/biometrics/presentation/access_display_page.dart';
import '../features/biometrics/presentation/biometric_settings_page.dart';
import '../features/biometrics/presentation/door_access_page.dart';
import '../features/biometrics/presentation/identify_reader_page.dart';
import '../features/biometrics/presentation/reader_diagnostic_page.dart';
import '../features/cash/presentation/cash_session_page.dart';
import '../features/dashboard/presentation/local_overview_page.dart';
import '../features/employees/presentation/employees_page.dart';
import '../features/enrollment/presentation/enrollment_wizard_page.dart';
import '../features/gyms/presentation/gyms_page.dart';
import '../features/gyms/presentation/create_gym_page.dart';
import '../features/members/presentation/member_detail_page.dart';
import '../features/members/presentation/member_form_page.dart';
import '../features/members/presentation/members_page.dart';
import '../features/messaging/presentation/campaigns_page.dart';
import '../features/onboarding/presentation/language_selection_page.dart';
import '../features/onboarding/presentation/onboarding_page.dart';
import '../features/onboarding/presentation/splash_page.dart';
import '../features/payments/presentation/payments_page.dart';
import '../features/plans/presentation/plans_page.dart';
import '../features/reports/presentation/reports_page.dart';
import '../features/settings/data/settings_repository.dart';
import '../features/settings/presentation/branding_page.dart';
import '../features/settings/presentation/pin_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/settings/presentation/sync_page.dart';
import '../features/staff/presentation/create_staff_page.dart';
import '../features/staff/presentation/staff_page.dart';
import '../features/subscriptions/presentation/pending_renewals_page.dart';
import '../features/billing/presentation/paywall_page.dart';
import '../l10n/app_strings.dart';
import 'runtime.dart';

String? _deferredLocation;

GoRouter createRouter(AppRuntime runtime) => GoRouter(
  initialLocation: '/startup',
  refreshListenable: runtime,
  redirect: (context, state) {
    final path = state.uri.path;
    final gate = switch (runtime.phase) {
      SessionPhase.starting => '/startup',
      SessionPhase.signedOut => runtime.onboardingDone
          ? '/login'
          : '/language',
      SessionPhase.recovery => '/reset-password',
      SessionPhase.locked => '/unlock',
      SessionPhase.blocked || SessionPhase.error =>
        runtime.errorCode == 'gym_suspended' ? '/paywall' : '/access',
      SessionPhase.ready => null,
    };
    // Fenèt ekran aksè a ouvri dirèkteman sou /access-display: kenbe destinasyon
    // an pandan demaraj la (/startup) pou retounen sou li lè sesyon an pare.
    if (path == '/access-display' && gate != null) _deferredLocation = path;
    if (gate == null && _deferredLocation != null && path != _deferredLocation) {
      final target = _deferredLocation;
      _deferredLocation = null;
      if (runtime.session?.isPlatformAdmin != true) return target;
    }
    if (gate == null && path == _deferredLocation) _deferredLocation = null;
    if (path == '/access-display' &&
        gate == null &&
        !{'owner', 'supervisor', 'reception'}.contains(runtime.session?.role)) {
      return '/';
    }
    if (gate != null) {
      if (runtime.phase == SessionPhase.signedOut &&
          {'/language', '/onboarding', '/signup', '/login'}.contains(path)) {
        return null;
      }
      if ((runtime.phase == SessionPhase.blocked ||
              runtime.phase == SessionPhase.error) &&
          path == '/paywall') {
        return null;
      }
      return path == gate ? null : gate;
    }
    // Mode kiosque : toute navigation est confinée au scanner.
    if (runtime.kioskLocked) {
      return path == '/kiosk' ? null : '/kiosk';
    }
    final platform = runtime.session?.isPlatformAdmin == true;
    if (path.startsWith('/gyms') && !platform) return '/';
    if (path.startsWith('/admin') && !platform) return '/';
    if (platform &&
        (path == '/' ||
            path == '/sync' ||
            path == '/door_access' ||
            path == '/scan' ||
            path == '/reports' ||
            path.startsWith('/campaigns') ||
            path.startsWith('/cash') ||
            path.startsWith('/members') ||
            path.startsWith('/plans') ||
            path.startsWith('/payments'))) {
      return '/gyms';
    }
    if (path == '/reports' &&
        !{'owner', 'supervisor'}.contains(runtime.session?.role)) {
      return '/';
    }
    if (path.startsWith('/campaigns') &&
        (platform ||
            !{'owner', 'supervisor'}.contains(runtime.session?.role))) {
      return '/';
    }
    if (path.startsWith('/cash') && platform) {
      return '/gyms';
    }
    if (path.startsWith('/settings/branding') &&
        (platform || runtime.session?.role != 'owner')) {
      return '/settings';
    }
    if (path.startsWith('/settings/staff') &&
        (platform || runtime.session?.role != 'owner')) {
      return '/settings';
    }
    if (path.startsWith('/settings/employees') &&
        (platform || runtime.session?.canManageGym != true)) {
      return '/settings';
    }
    if (path.startsWith('/badges') ||
        path.startsWith('/activate') ||
        path.startsWith('/settings/badges')) {
      return '/';
    }
    if (path.startsWith('/subscriptions/renewals') &&
        (platform ||
            !{'owner', 'supervisor'}.contains(runtime.session?.role))) {
      return '/';
    }
    return {
          '/startup',
          '/language',
          '/login',
          '/access',
          '/reset-password',
          '/unlock',
          '/onboarding',
          '/signup',
        }.contains(path)
        ? (platform ? '/gyms' : '/')
        : null;
  },
  errorBuilder: (context, state) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: MessagePanel(
          message: AppStrings.of(context).text('error'),
          action: AppStrings.of(context).text('home'),
          onAction: () => context.go('/'),
        ),
      ),
    ),
  ),
  routes: [
    GoRoute(
      path: '/startup',
      builder: (context, state) => const SplashPage(),
    ),
    GoRoute(
      path: '/language',
      builder: (context, state) => const LanguageSelectionPage(),
    ),
    GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const OnboardingPage(),
    ),
    GoRoute(
      path: '/signup',
      builder: (context, state) => const SignupPage(),
    ),
    GoRoute(
      path: '/paywall',
      builder: (context, state) => const PaywallPage(),
    ),
    GoRoute(
      path: '/kiosk',
      builder: (context, state) => const KioskPage(),
    ),
    // Ekran aksè pou 2yèm ekran devan pòt la (fenèt apa, plen ekran).
    GoRoute(
      path: '/access-display',
      builder: (context, state) => const AccessDisplayPage(),
    ),
    GoRoute(
      path: '/reset-password',
      builder: (context, state) => const PasswordResetPage(),
    ),
    GoRoute(path: '/unlock', builder: (context, state) => const UnlockPage()),
    GoRoute(
      path: '/access',
      builder: (context, state) => _AccessPage(runtime: runtime),
    ),
    GoRoute(
      path: '/gyms/new',
      builder: (context, state) => const CreateGymPage(),
    ),
    ShellRoute(
      builder: (context, state, child) => AccessPopupOverlay(
        runtime: runtime,
        child: _AppShell(runtime: runtime, location: state.uri.path, child: child),
      ),
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const LocalOverviewPage(),
        ),
        GoRoute(
          path: '/members',
          builder: (context, state) => const MembersPage(),
        ),
        GoRoute(
          path: '/members/new',
          builder: (context, state) => const EnrollmentWizardPage(),
        ),
        GoRoute(
          path: '/members/:id',
          builder: (context, state) =>
              MemberDetailPage(memberId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/members/:id/edit',
          builder: (context, state) =>
              MemberFormPage(memberId: state.pathParameters['id']),
        ),
        GoRoute(
          path: '/members/:id/badge',
          builder: (context, state) =>
              MemberDetailPage(memberId: state.pathParameters['id']!),
        ),
        GoRoute(path: '/plans', builder: (context, state) => const PlansPage()),
        GoRoute(
          path: '/payments',
          builder: (context, state) => const PaymentsPage(),
        ),
        GoRoute(
          path: '/campaigns',
          builder: (context, state) => const CampaignsPage(),
        ),
        GoRoute(
          path: '/cash',
          builder: (context, state) => const CashSessionPage(),
        ),
        GoRoute(
          path: '/reports',
          builder: (context, state) => const ReportsPage(),
        ),
        GoRoute(path: '/door_access', builder: (context, state) => const DoorAccessPage()),
        GoRoute(path: '/scan', redirect: (context, state) => '/door_access'),
        GoRoute(path: '/sync', builder: (context, state) => const SyncPage()),
        GoRoute(
          path: '/badges',
          redirect: (context, state) => '/door_access',
        ),
        GoRoute(
          path: '/activate',
          redirect: (context, state) => '/members',
        ),
        GoRoute(
          path: '/subscriptions/renewals',
          builder: (context, state) => const PendingRenewalsPage(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsPage(),
        ),
        GoRoute(
          path: '/settings/biometrics',
          builder: (context, state) => const BiometricSettingsPage(),
        ),
        GoRoute(
          path: '/settings/biometrics/identify',
          builder: (context, state) => const IdentifyReaderPage(),
        ),
        GoRoute(
          path: '/settings/biometrics/diagnostic',
          builder: (context, state) => const ReaderDiagnosticPage(),
        ),
        GoRoute(
          path: '/settings/branding',
          builder: (context, state) => const BrandingPage(),
        ),
        GoRoute(
          path: '/settings/badges',
          redirect: (context, state) => '/settings/biometrics',
        ),
        GoRoute(
          path: '/settings/pin',
          builder: (context, state) => const PinPage(),
        ),
        GoRoute(
          path: '/settings/staff',
          builder: (context, state) => const StaffPage(),
        ),
        GoRoute(
          path: '/settings/staff/new',
          builder: (context, state) => const CreateStaffPage(),
        ),
        GoRoute(
          path: '/settings/employees',
          builder: (context, state) => const EmployeesPage(),
        ),
        GoRoute(path: '/gyms', builder: (context, state) => const GymsPage()),
        GoRoute(
          path: '/admin/declarations',
          builder: (context, state) => const DeclarationsPage(),
        ),
        GoRoute(
          path: '/admin/offers',
          builder: (context, state) => const OffersPage(),
        ),
        GoRoute(
          path: '/admin/email',
          builder: (context, state) => const EmailSettingsPage(),
        ),
      ],
    ),
  ],
);

class _AccessPage extends StatelessWidget {
  const _AccessPage({required this.runtime});
  final AppRuntime runtime;
  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MessagePanel(
                    message: s.text(runtime.errorCode ?? 'error'),
                    action: s.text('retry'),
                    onAction: runtime.refresh,
                    icon: LucideIcons.shieldAlert,
                  ),
                  TextButton(
                    onPressed: runtime.signOut,
                    child: Text(s.text('sign_out')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AppShell extends StatelessWidget {
  const _AppShell({
    required this.runtime,
    required this.location,
    required this.child,
  });
  final AppRuntime runtime;
  final String location;
  final Widget child;
  List<String> get _paths => runtime.session?.isPlatformAdmin == true
      ? ['/gyms', '/admin/offers', '/admin/declarations', '/admin/email', '/settings']
      : {'owner', 'supervisor'}.contains(runtime.session?.role)
      ? [
          '/',
          '/members',
          '/door_access',
          '/campaigns',
          '/cash',
          '/plans',
          '/payments',
          '/reports',
          '/sync',
          '/settings',
        ]
      : [
          '/',
          '/members',
          '/door_access',
          '/cash',
          '/plans',
          '/payments',
          '/sync',
          '/settings',
        ];
  List<String> get _narrowPaths => runtime.session?.isPlatformAdmin == true
      ? _paths
      : ['/', '/members', '/door_access', '/cash', '/settings'];
  List<String> get _narrowKeys => runtime.session?.isPlatformAdmin == true
      ? _keys
      : ['home', 'members', 'door_access', 'cash', 'settings'];
  List<IconData> get _narrowIcons => runtime.session?.isPlatformAdmin == true
      ? _icons
      : [
          LucideIcons.house,
          LucideIcons.users,
          LucideIcons.fingerprint,
          LucideIcons.wallet,
          LucideIcons.settings,
        ];
  List<String> get _keys => runtime.session?.isPlatformAdmin == true
      ? ['gyms', 'offers', 'declarations', 'email_admin', 'settings']
      : {'owner', 'supervisor'}.contains(runtime.session?.role)
      ? [
          'home',
          'members',
          'door_access',
          'campaigns',
          'cash',
          'plans',
          'payments',
          'reports',
          'sync',
          'settings',
        ]
      : [
          'home',
          'members',
          'door_access',
          'cash',
          'plans',
          'payments',
          'sync',
          'settings',
        ];
  List<IconData> get _icons => runtime.session?.isPlatformAdmin == true
      ? [
          LucideIcons.building2,
          LucideIcons.tag,
          LucideIcons.clipboardCheck,
          LucideIcons.mail,
          LucideIcons.settings,
        ]
      : {'owner', 'supervisor'}.contains(runtime.session?.role)
      ? [
          LucideIcons.house,
          LucideIcons.users,
          LucideIcons.fingerprint,
          LucideIcons.mail,
          LucideIcons.wallet,
          LucideIcons.badgeDollarSign,
          LucideIcons.banknote,
          LucideIcons.chartColumn,
          LucideIcons.refreshCw,
          LucideIcons.settings,
        ]
      : [
          LucideIcons.house,
          LucideIcons.users,
          LucideIcons.fingerprint,
          LucideIcons.wallet,
          LucideIcons.badgeDollarSign,
          LucideIcons.banknote,
          LucideIcons.refreshCw,
          LucideIcons.settings,
        ];

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final index = _paths.indexWhere(
      (path) => location == path || location.startsWith('$path/'),
    );
    final selected = index < 0 ? 0 : index;
    return Listener(
      onPointerDown: (_) => runtime.activity(),
      child: Focus(
        onKeyEvent: (node, event) {
          runtime.activity();
          return KeyEventResult.ignored;
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isScan = location == '/scan' || location == '/kiosk' || runtime.kioskLocked;
            if (isScan) {
              return Scaffold(
                body: SafeArea(child: child),
              );
            }
            final wide = constraints.maxWidth >= 800;
            final isExtended = constraints.maxWidth >= 1200;
            return Scaffold(
              appBar: AppBar(
                title: Row(
                  children: [
                    Flexible(
                      child: Text(
                        runtime.session?.name ?? 'SecurGYM',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Tooltip(
                      message: 'Sécurisé par SecurGYM',
                      child: Image.asset(
                        'assets/brand/icon_securgym.png',
                        width: 20,
                        height: 20,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ],
                ),
                actions: [
                  if (runtime.sync != null)
                    ListenableBuilder(
                      listenable: runtime,
                      builder: (context, _) {
                        final state = runtime.sync!.state.value;
                        final key = switch (state.phase) {
                          SyncPhase.idle => 'online',
                          SyncPhase.offline => 'offline',
                          SyncPhase.running => 'running',
                          SyncPhase.blocked || SyncPhase.error => 'error',
                        };
                        return TextButton.icon(
                          onPressed: () => context.go('/sync'),
                          icon: Icon(
                            state.phase == SyncPhase.offline
                                ? LucideIcons.wifiOff
                                : LucideIcons.refreshCw,
                            size: 18,
                          ),
                          label: Text(
                            '${s.text(key)}${state.pending + state.failed > 0 ? ' · ${state.pending + state.failed}' : ''}',
                          ),
                        );
                      },
                    ),
                  const SizedBox(width: 12),
                ],
              ),
              body: Row(
                children: [
                  if (wide) ...[
                    NavigationRail(
                      selectedIndex: selected,
                      extended: isExtended,
                      minExtendedWidth: 220,
                      leading: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: _GymLogo(
                          runtime: runtime,
                          extended: isExtended,
                        ),
                      ),
                      trailing: Expanded(
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: isExtended
                                ? Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Image.asset(
                                        'assets/brand/icon_securgym.png',
                                        width: 16,
                                        height: 16,
                                      ),
                                      const SizedBox(width: 6),
                                      const Text(
                                        'SecurGYM',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xff9ca3af),
                                        ),
                                      ),
                                    ],
                                  )
                                : Image.asset(
                                    'assets/brand/icon_securgym.png',
                                    width: 16,
                                    height: 16,
                                  ),
                          ),
                        ),
                      ),
                      labelType: isExtended
                          ? NavigationRailLabelType.none
                          : NavigationRailLabelType.all,
                      onDestinationSelected: (index) =>
                          context.go(_paths[index]),
                      destinations: List.generate(
                        _paths.length,
                        (i) => NavigationRailDestination(
                          icon: Icon(_icons[i]),
                          label: Text(s.text(_keys[i])),
                        ),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                  ],
                  Expanded(child: child),
                ],
              ),
              bottomNavigationBar: wide
                  ? null
                  : Builder(
                      builder: (context) {
                        final narrowIndex = _narrowPaths.indexWhere(
                          (path) =>
                              location == path ||
                              location.startsWith('$path/'),
                        );
                        return NavigationBar(
                          selectedIndex: narrowIndex < 0
                              ? _narrowPaths.length - 1
                              : narrowIndex,
                          onDestinationSelected: (index) =>
                              context.go(_narrowPaths[index]),
                          destinations: List.generate(
                            _narrowPaths.length,
                            (i) => NavigationDestination(
                              icon: Icon(_narrowIcons[i]),
                              label: s.text(_narrowKeys[i]),
                            ),
                          ),
                        );
                      },
                    ),
            );
          },
        ),
      ),
    );
  }
}

/// Logo gym nan nan ba navigasyon an — telechaje URL siyen a yon fwa.
/// Tounen sou logo SecurGYM si gym nan pa gen logo.
class _GymLogo extends StatefulWidget {
  const _GymLogo({required this.runtime, required this.extended});
  final AppRuntime runtime;
  final bool extended;

  @override
  State<_GymLogo> createState() => _GymLogoState();
}

class _GymLogoState extends State<_GymLogo> {
  String? _url;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final runtime = widget.runtime;
      final db = runtime.database;
      final session = runtime.session;
      if (db == null || session == null) return;
      final url = await GymSettingsRepository(
        runtime.client,
        db,
        session,
      ).signedLogoUrl(session.gym?['logo_url'] as String?);
      if (mounted) {
        setState(() {
          _url = url;
          _loaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = _url;
    if (_loaded && url != null) {
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: widget.extended ? 180 : 56,
          maxHeight: widget.extended ? 64 : 56,
        ),
        child: Image.network(url, fit: BoxFit.contain,
            errorBuilder: (_, _, _) => _fallback()),
      );
    }
    return _fallback();
  }

  Widget _fallback() => widget.extended
      ? Image.asset(
          'assets/brand/logo_horizontal.png',
          width: 150,
          fit: BoxFit.contain,
        )
      : Image.asset(
          'assets/brand/icon_securgym.png',
          width: 34,
          height: 34,
          fit: BoxFit.contain,
        );
}
