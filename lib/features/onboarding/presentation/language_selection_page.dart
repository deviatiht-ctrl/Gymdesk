import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/providers.dart';
import '../../../l10n/app_strings.dart';

import '../../../core/widgets/securgym_background.dart';

class LanguageSelectionPage extends ConsumerStatefulWidget {
  const LanguageSelectionPage({super.key});

  @override
  ConsumerState<LanguageSelectionPage> createState() => _LanguageSelectionPageState();
}

class _LanguageSelectionPageState extends ConsumerState<LanguageSelectionPage> {
  String _selected = 'ht';

  final _languages = const [
    {
      'code': 'ht',
      'flag': '🇭🇹',
      'name': 'Kreyòl Ayisyen',
      'subtitle': 'Lang natif natal pou sal fòs an Ayiti',
    },
    {
      'code': 'fr',
      'flag': '🇫🇷',
      'name': 'Français',
      'subtitle': 'Français standard pour votre gestion',
    },
    {
      'code': 'en',
      'flag': '🇺🇸',
      'name': 'English',
      'subtitle': 'International English version',
    },
  ];

  @override
  void initState() {
    super.initState();
    _selected = ref.read(appLanguageProvider).languageCode;
  }

  void _choose(String code) {
    setState(() => _selected = code);
    ref.read(appLanguageProvider.notifier).change(code);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    const brandOrange = Color(0xffff6600);

    return Scaffold(
      backgroundColor: const Color(0xff121417),
      body: SecurGymBackground(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: const Color(0xff1a1d24).withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Anblèm Boukliye SecurGYM
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: brandOrange.withValues(alpha: 0.3),
                            blurRadius: 24,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Image.asset(
                        'assets/brand/icon_securgym.png',
                        width: 76,
                        height: 76,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      s.text('language_selection_title'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      s.text('language_selection_subtitle'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xff9ca3af),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Liste des 3 langues
                    for (final item in _languages) ...[
                      Card(
                        color: _selected == item['code']
                            ? brandOrange.withValues(alpha: 0.12)
                            : const Color(0xff222630),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: _selected == item['code']
                                ? brandOrange
                                : Colors.white.withValues(alpha: 0.08),
                            width: _selected == item['code'] ? 2 : 1,
                          ),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => _choose(item['code']!),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                            child: Row(
                              children: [
                                Text(item['flag']!, style: const TextStyle(fontSize: 28)),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item['name']!,
                                        style: theme.textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        item['subtitle']!,
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: const Color(0xff9ca3af),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Radio<String>(
                                  value: item['code']!,
                                  groupValue: _selected,
                                  activeColor: brandOrange,
                                  onChanged: (v) => _choose(v!),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: brandOrange,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(LucideIcons.arrowRight),
                        label: Text(
                          s.text('continue_button'),
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () {
                          context.go('/onboarding');
                        },
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
