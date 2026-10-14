import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/providers.dart';
import '../../../l10n/app_strings.dart';

import '../../../core/widgets/securgym_background.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});
  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _controller = PageController();
  int _index = 0;

  static const _titles = [
    'onboarding_title_1',
    'onboarding_title_2',
    'onboarding_title_3',
    'onboarding_title_4',
  ];
  static const _bodies = [
    'onboarding_body_1',
    'onboarding_body_2',
    'onboarding_body_3',
    'onboarding_body_4',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish({required bool signup}) async {
    await ref.read(appRuntimeProvider).completeOnboarding();
    if (mounted) context.go(signup ? '/signup' : '/login');
  }

  Widget _buildSlideVisual(int index, ThemeData theme) {
    const brandOrange = Color(0xffff6600);

    switch (index) {
      case 0:
        // Visual 1: SecurGYM — Jesyon & Sekirite Total
        return Container(
          height: 210,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xff181b22),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: brandOrange.withValues(alpha: 0.3)),
            boxShadow: [
              BoxShadow(
                color: brandOrange.withValues(alpha: 0.15),
                blurRadius: 24,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: brandOrange.withValues(alpha: 0.15),
                ),
                child: Image.asset(
                  'assets/brand/icon_securgym.png',
                  width: 58,
                  height: 58,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 12),
              Image.asset(
                'assets/brand/logo_horizontal.png',
                width: 170,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _badgeTag(LucideIcons.shieldCheck, 'Sekirite Avanse', brandOrange),
                  const SizedBox(width: 8),
                  _badgeTag(LucideIcons.monitorSmartphone, 'PC · Tablèt · Telefòn', const Color(0xff9ca3af)),
                ],
              ),
            ],
          ),
        );

      case 1:
        // Visual 2: Kontwòl Aksè Byometrik (Anprent Dijital)
        return Container(
          height: 210,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xff181b22),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Row(
            children: [
              // Scanner Byometrik
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: brandOrange.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: brandOrange, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: brandOrange.withValues(alpha: 0.3),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(LucideIcons.fingerprint, size: 54, color: brandOrange),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.check, size: 14, color: Colors.green),
                          SizedBox(width: 4),
                          Text(
                            'ANPRENT VALIDE · 0.2s',
                            style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      '« Aksè Pòt Debloke »',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Lektè USB Byometrik · San kat pou pèdi',
                      style: TextStyle(color: Color(0xff9ca3af), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

      case 2:
        // Visual 3: Jesyon Manm & Notifikasyon Imèl Otomatik
        return Container(
          height: 210,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xff181b22),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: brandOrange.withValues(alpha: 0.2),
                    child: const Icon(LucideIcons.user, color: brandOrange, size: 24),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Marc Jean-Baptiste',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Abònman Aktif · Fòmil VIP 30 Jou',
                          style: TextStyle(color: Color(0xff9ca3af), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'ACTIF',
                      style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 10),
                    ),
                  ),
                ],
              ),
              const Divider(color: Color(0xff2a2e39), height: 24),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: brandOrange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(LucideIcons.mailCheck, size: 20, color: brandOrange),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Notifikasyon Imèl Otomatik',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Resi peman PDF & rapèl voye otomatikman bay manm lan',
                          style: TextStyle(color: Color(0xff9ca3af), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

      case 3:
      default:
        // Visual 4: Suivi Finans & Resi Sekirize SecurGYM
        return Container(
          height: 210,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xff181b22),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 6,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(LucideIcons.wallet, color: brandOrange, size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          'Revni Mwa Sa a',
                          style: TextStyle(color: Color(0xff9ca3af), fontSize: 12),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            '+24%',
                            style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '250,000 HTG',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(LucideIcons.fileCheck2, size: 14, color: brandOrange),
                        const SizedBox(width: 6),
                        const Text(
                          'Resi PDF ak Kòd QR SecurGYM',
                          style: TextStyle(color: Color(0xff9ca3af), fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              // Mini QR Preview
              Container(
                width: 80,
                height: 80,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Image.asset(
                  'assets/brand/securegymqr.png',
                  fit: BoxFit.contain,
                ),
              ),
            ],
          ),
        );
    }
  }

  Widget _badgeTag(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  void _showLanguagePicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xff1a1d24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final current = ref.watch(appLanguageProvider).languageCode;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Text('🇭🇹', style: TextStyle(fontSize: 24)),
                  title: const Text('Kreyòl Ayisyen', style: TextStyle(color: Colors.white)),
                  trailing: current == 'ht' ? const Icon(Icons.check, color: Color(0xffff6600)) : null,
                  onTap: () {
                    ref.read(appLanguageProvider.notifier).change('ht');
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  leading: const Text('🇫🇷', style: TextStyle(fontSize: 24)),
                  title: const Text('Français', style: TextStyle(color: Colors.white)),
                  trailing: current == 'fr' ? const Icon(Icons.check, color: Color(0xffff6600)) : null,
                  onTap: () {
                    ref.read(appLanguageProvider.notifier).change('fr');
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  leading: const Text('🇺🇸', style: TextStyle(fontSize: 24)),
                  title: const Text('English', style: TextStyle(color: Colors.white)),
                  trailing: current == 'en' ? const Icon(Icons.check, color: Color(0xffff6600)) : null,
                  onTap: () {
                    ref.read(appLanguageProvider.notifier).change('en');
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    final last = _index == _titles.length - 1;
    final currentLang = ref.watch(appLanguageProvider).languageCode;
    const brandOrange = Color(0xffff6600);

    return Scaffold(
      backgroundColor: const Color(0xff121417),
      body: SecurGymBackground(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                color: const Color(0xff1a1d24).withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 32,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // En-tête avec changement de langue et passer
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ActionChip(
                        backgroundColor: const Color(0xff222630),
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                        avatar: Text(
                          currentLang == 'ht' ? '🇭🇹' : currentLang == 'fr' ? '🇫🇷' : '🇺🇸',
                          style: const TextStyle(fontSize: 16),
                        ),
                        label: Text(
                          currentLang == 'ht' ? 'Kreyòl' : currentLang == 'fr' ? 'Français' : 'English',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        onPressed: _showLanguagePicker,
                      ),
                      TextButton(
                        onPressed: () => _finish(signup: false),
                        child: Text(s.text('skip'), style: const TextStyle(color: Color(0xff9ca3af))),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: PageView.builder(
                      controller: _controller,
                      itemCount: _titles.length,
                      onPageChanged: (i) => setState(() => _index = i),
                      itemBuilder: (context, i) => SingleChildScrollView(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(height: 12),
                            _buildSlideVisual(i, theme),
                            const SizedBox(height: 24),
                            Text(
                              s.text(_titles[i]),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              s.text(_bodies[i]),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: const Color(0xff9ca3af),
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _titles.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: i == _index ? 28 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: i == _index ? brandOrange : const Color(0xff374151),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (last)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: brandOrange,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(50),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: () => _finish(signup: true),
                          icon: const Icon(LucideIcons.sparkles),
                          label: Text(s.text('create_gym_trial'), style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xff374151)),
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: () => _finish(signup: false),
                          child: Text(s.text('i_have_account')),
                        ),
                      ],
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: brandOrange,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: () => _controller.nextPage(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                        ),
                        child: Text(s.text('next'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
