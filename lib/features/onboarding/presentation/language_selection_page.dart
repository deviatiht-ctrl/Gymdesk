import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/providers.dart';
import '../../../l10n/app_strings.dart';

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
    final colors = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo de marque
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset(
                      'assets/images/app_icon.png',
                      width: 80,
                      height: 80,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: colors.primary.withAlpha(24),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(LucideIcons.dumbbell, size: 40, color: colors.primary),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    s.text('language_selection_title'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    s.text('language_selection_subtitle'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.outline,
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Liste des 3 langues
                  for (final item in _languages) ...[
                    Card(
                      elevation: _selected == item['code'] ? 2 : 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: _selected == item['code']
                              ? colors.primary
                              : colors.outlineVariant,
                          width: _selected == item['code'] ? 2 : 1,
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => _choose(item['code']!),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          child: Row(
                            children: [
                              Text(item['flag']!, style: const TextStyle(fontSize: 32)),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item['name']!,
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      item['subtitle']!,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: colors.outline,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Radio<String>(
                                value: item['code']!,
                                groupValue: _selected,
                                onChanged: (v) => _choose(v!),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      icon: const Icon(LucideIcons.arrowRight),
                      label: Text(
                        s.text('continue_button'),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
    );
  }
}
