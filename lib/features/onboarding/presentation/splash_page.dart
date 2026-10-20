import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/runtime.dart';

import '../../../core/widgets/securgym_background.dart';

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
    final baseUri = Uri.base;
    if (baseUri.path.startsWith('/join') ||
        baseUri.path.startsWith('/portal') ||
        baseUri.path.startsWith('/kiosk')) {
      return;
    }
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
    const brandOrange = Color(0xffff6600);

    return Scaffold(
      backgroundColor: const Color(0xff121417),
      body: SecurGymBackground(
        useSafeArea: false,
        child: Center(
          child: AnimatedBuilder(
            animation: _animController,
            builder: (context, child) => FadeTransition(
              opacity: _opacityAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Anblèm Boukliye SecurGYM
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: brandOrange.withValues(alpha: 0.35),
                            blurRadius: 36,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: Image.asset(
                        'assets/brand/icon_securgym.png',
                        width: 120,
                        height: 120,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Logo Orizontal SecurGYM
                    Image.asset(
                      'assets/brand/logo_horizontal.png',
                      width: 250,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Sécurité et gestion de votre gym',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.8,
                        color: Color(0xffc5cad4),
                      ),
                    ),
                    const SizedBox(height: 36),
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(brandOrange),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
