import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/providers.dart';
import '../../../l10n/app_strings.dart';

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
    switch (index) {
      case 0:
        return ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Image.asset(
            'assets/images/onboarding_badges.jpg',
            height: 220,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _fallbackHero(theme, LucideIcons.idCard, 'GymDesk Badges'),
          ),
        );
      case 1:
        // Visual Finance & Revenus
        return Container(
          height: 200,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                theme.colorScheme.primaryContainer,
                theme.colorScheme.surfaceContainerHighest,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(LucideIcons.wallet, color: theme.colorScheme.primary, size: 28),
                      const SizedBox(width: 10),
                      Text(
                        'Revenu Mensuel & Annuel',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withAlpha(40),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      '+24% ce mois',
                      style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _statCol('Mois en cours', '250,000 HTG', LucideIcons.trendingUp, theme),
                  Container(width: 1, height: 40, color: theme.colorScheme.outlineVariant),
                  _statCol('Cumul Annuel', '1,850,000 HTG', LucideIcons.calendarCheck, theme),
                ],
              ),
              Row(
                children: [
                  Icon(LucideIcons.shieldCheck, size: 16, color: theme.colorScheme.outline),
                  const SizedBox(width: 6),
                  Text(
                    'Suivi en temps réel des abonnements actifs',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                  ),
                ],
              ),
            ],
          ),
        );
      case 2:
        // Visual Pointage QR + PIN
        return Container(
          height: 200,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withAlpha(30),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '✓ SCAN VALIDÉ',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '« Bienvenue, Marc ! »',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Code PIN vérifié · Entrée #1 aujourd’hui',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.primary, width: 2),
                ),
                child: Icon(LucideIcons.qrCode, size: 54, color: theme.colorScheme.primary),
              ),
            ],
          ),
        );
      case 3:
      default:
        // Visual Activation & Photo ID
        return Container(
          height: 200,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 44,
                backgroundColor: theme.colorScheme.primary.withAlpha(30),
                child: Icon(LucideIcons.camera, size: 40, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Photo Instantanée',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Capturez le visage du membre, attribuez le badge et exportez vos lots sur clé USB.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(LucideIcons.usb, size: 16, color: theme.colorScheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          'Export Planche A4 / USB',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
    }
  }

  Widget _statCol(String title, String value, IconData icon, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: theme.colorScheme.primary),
            const SizedBox(width: 4),
            Text(title, style: theme.textTheme.labelSmall),
          ],
        ),
        const SizedBox(height: 4),
        Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _fallbackHero(ThemeData theme, IconData icon, String label) {
    return Container(
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 10),
            Text(label, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  void _showLanguagePicker() {
    showModalBottomSheet<void>(
      context: context,
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
                  title: const Text('Kreyòl Ayisyen'),
                  trailing: current == 'ht' ? const Icon(Icons.check, color: Colors.green) : null,
                  onTap: () {
                    ref.read(appLanguageProvider.notifier).change('ht');
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  leading: const Text('🇫🇷', style: TextStyle(fontSize: 24)),
                  title: const Text('Français'),
                  trailing: current == 'fr' ? const Icon(Icons.check, color: Colors.green) : null,
                  onTap: () {
                    ref.read(appLanguageProvider.notifier).change('fr');
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  leading: const Text('🇺🇸', style: TextStyle(fontSize: 24)),
                  title: const Text('English'),
                  trailing: current == 'en' ? const Icon(Icons.check, color: Colors.green) : null,
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

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                children: [
                  // En-tête avec changement de langue et passer
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ActionChip(
                        avatar: Text(
                          currentLang == 'ht' ? '🇭🇹' : currentLang == 'fr' ? '🇫🇷' : '🇺🇸',
                          style: const TextStyle(fontSize: 16),
                        ),
                        label: Text(
                          currentLang == 'ht' ? 'Kreyòl' : currentLang == 'fr' ? 'Français' : 'English',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        onPressed: _showLanguagePicker,
                      ),
                      TextButton(
                        onPressed: () => _finish(signup: false),
                        child: Text(s.text('skip')),
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
                            const SizedBox(height: 16),
                            _buildSlideVisual(i, theme),
                            const SizedBox(height: 28),
                            Text(
                              s.text(_titles[i]),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              s.text(_bodies[i]),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.outline,
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
                          color: i == _index
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outlineVariant,
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
                          onPressed: () => _finish(signup: true),
                          icon: const Icon(LucideIcons.sparkles),
                          label: Text(s.text('create_gym_trial')),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: () => _finish(signup: false),
                          child: Text(s.text('i_have_account')),
                        ),
                      ],
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                        onPressed: () => _controller.nextPage(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                        ),
                        child: Text(s.text('next')),
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
