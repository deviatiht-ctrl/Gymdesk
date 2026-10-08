import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/runtime.dart';

class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage> with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _opacityAnimation;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );
    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeIn),
    );

    _animController.forward();

    // 1.2 segonn pou animasyon an fini nèt epi pase sou pwochen ekran imedyatman
    _timer = Timer(const Duration(milliseconds: 1200), _navigateNext);
  }

  void _navigateNext() {
    if (!mounted) return;
    final runtime = ref.read(appRuntimeProvider);
    if (!runtime.onboardingDone) {
      context.go('/language');
    } else if (runtime.phase == SessionPhase.ready) {
      context.go('/');
    } else if (runtime.phase != SessionPhase.starting) {
      context.go('/login');
    } else {
      // Si runtime toujou ap inisyalize, tcheke ankò nan 300ms
      _timer = Timer(const Duration(milliseconds: 300), _navigateNext);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      backgroundColor: colors.surface,
      body: Center(
        child: AnimatedBuilder(
          animation: _animController,
          builder: (context, child) => FadeTransition(
            opacity: _opacityAnimation,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo ou Icône de marque
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.asset(
                      'assets/images/app_icon.png',
                      width: 110,
                      height: 110,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => Container(
                        width: 110,
                        height: 110,
                        decoration: BoxDecoration(
                          color: colors.primary.withAlpha(24),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Icon(Icons.fitness_center, size: 54, color: colors.primary),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Image.asset(
                    'assets/images/gymdesk_logo.png',
                    width: 220,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => Text(
                      'GymDesk',
                      style: theme.textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: colors.primary,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 36),
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: colors.primary,
                    ),
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
