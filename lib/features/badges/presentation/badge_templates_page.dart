import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/async_panel.dart';
import '../../../l10n/app_strings.dart';
import '../data/badge_templates_repository.dart';
import '../domain/badge_template.dart';
import '../domain/badge_background_themes.dart';

class BadgeTemplatesPage extends ConsumerStatefulWidget {
  const BadgeTemplatesPage({super.key});
  @override
  ConsumerState<BadgeTemplatesPage> createState() => _BadgeTemplatesPageState();
}

class _BadgeTemplatesPageState extends ConsumerState<BadgeTemplatesPage> {
  late final BadgeTemplatesRepository _repository;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final runtime = ref.read(appRuntimeProvider);
    _repository = BadgeTemplatesRepository(runtime.database!, runtime.session!);
  }

  DateTime get _now =>
      ref.read(appRuntimeProvider).sync?.clock.correctedNow ??
      DateTime.now().toUtc();
  void _error(String code) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(AppStrings.of(context).text(code))));

  Future<void> _edit([BadgeTemplate? template]) async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final form = GlobalKey<FormState>();
    final name = TextEditingController(text: template?.name ?? '');
    final accent = TextEditingController(text: template?.accentColor ?? '');
    var orientation = template?.orientation ?? 'landscape';
    var photo = template?.showPhoto ?? true;
    var qr = template?.showQr ?? true;
    var gym = template?.showGymName ?? true;
    var status = template?.showStatus ?? true;
    var isDefault = template?.isDefault ?? false;
    var themeId = template?.backgroundThemeId ?? 'dark_carbon_gold';
    var qrStyle = template?.qrStyle ?? 'rounded';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(s.text(template == null ? 'new_badge_template' : 'edit')),
          content: Form(
            key: form,
            child: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: name,
                      decoration: InputDecoration(
                        labelText: s.text('badge_template_name'),
                      ),
                      validator: (v) => (v?.trim().length ?? 0) < 2
                          ? s.text('invalid_record')
                          : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: orientation,
                      decoration: InputDecoration(
                        labelText: s.text('orientation'),
                      ),
                      items: ['landscape', 'portrait']
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(s.text('orientation_$value')),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => orientation = v ?? 'landscape',
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: themeId,
                      decoration: InputDecoration(
                        labelText: s.text('badge_background_theme'),
                      ),
                      items: BadgeBackgroundTheme.themes
                          .map(
                            (th) => DropdownMenuItem(
                              value: th.id,
                              child: Text(' ()'),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => themeId = v ?? 'dark_carbon_gold',
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: qrStyle,
                      decoration: InputDecoration(
                        labelText: s.text('badge_qr_style'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'rounded',
                          child: Text(s.text('badge_qr_rounded')),
                        ),
                        DropdownMenuItem(
                          value: 'square',
                          child: Text(s.text('badge_qr_square')),
                        ),
                        DropdownMenuItem(
                          value: 'circle',
                          child: Text(s.text('badge_qr_circle')),
                        ),
                      ],
                      onChanged: (v) => qrStyle = v ?? 'rounded',
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: accent,
                      decoration: InputDecoration(
                        labelText: s.text('badge_accent'),
                        hintText: '#1F6F4A',
                      ),
                      validator: (v) =>
                          v == null ||
                              v.isEmpty ||
                              RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(v)
                          ? null
                          : s.text('accent_hint'),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(s.text('show_photo')),
                      value: photo,
                      onChanged: (v) => setDialog(() => photo = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(s.text('show_qr')),
                      value: qr,
                      onChanged: (v) => setDialog(() => qr = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(s.text('show_gym_name')),
                      value: gym,
                      onChanged: (v) => setDialog(() => gym = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(s.text('show_status')),
                      value: status,
                      onChanged: (v) => setDialog(() => status = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(s.text('default_template')),
                      subtitle: Text(s.text('default_template_hint')),
                      value: isDefault,
                      onChanged: (v) => setDialog(() => isDefault = v),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.text('cancel')),
            ),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) Navigator.pop(context, true);
              },
              child: Text(s.text('save')),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) {
      name.dispose();
      accent.dispose();
      return;
    }
    setState(() => _busy = true);
    try {
      await _repository.save(
        BadgeTemplateDraft(
          name: name.text,
          orientation: orientation,
          showPhoto: photo,
          showQr: qr,
          showGymName: gym,
          showStatus: status,
          accentColor: accent.text.trim(),
          backgroundThemeId: themeId,
          qrStyle: qrStyle,
          isDefault: isDefault,
        ),
        existing: template,
        changedAt: _now,
      );
      await ref.read(appRuntimeProvider).sync?.synchronize();
    } on BadgeFailure catch (e) {
      _error(e.code);
    } finally {
      name.dispose();
      accent.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await ref.read(appRuntimeProvider).sync?.synchronize();
    } on BadgeFailure catch (e) {
      _error(e.code);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final role = ref.watch(appRuntimeProvider).session?.role;
    final canEdit = {'owner', 'supervisor'}.contains(role);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 24,
            runSpacing: 16,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.text('badge_templates'),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  Text(s.text('badge_templates_hint')),
                ],
              ),
              if (canEdit)
                FilledButton.icon(
                  onPressed: _busy ? null : () => _edit(),
                  icon: const Icon(LucideIcons.plus),
                  label: Text(s.text('new_badge_template')),
                ),
            ],
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
        Expanded(
          child: StreamBuilder<List<BadgeTemplate>>(
            stream: _repository.watch(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: MessagePanel(message: s.text('local_storage')),
                );
              }
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: LoadingPanel(),
                );
              }
              if (snapshot.data!.isEmpty) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: MessagePanel(
                    message: s.text('badge_templates_empty'),
                    action: canEdit ? s.text('new_badge_template') : null,
                    onAction: canEdit ? () => _edit() : null,
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: snapshot.data!.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final template = snapshot.data![index];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    leading: Icon(
                      template.orientation == 'portrait'
                          ? LucideIcons.smartphone
                          : LucideIcons.rectangleHorizontal,
                    ),
                    title: Text(template.name),
                    subtitle: Text(
                      '${s.text('orientation_${template.orientation}')} Â· ${template.showPhoto ? s.text('show_photo') : s.text('no_photo')} Â· ${template.showQr ? 'QR' : s.text('no_qr')}',
                    ),
                    trailing: Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (template.isDefault)
                          Chip(label: Text(s.text('default_badge')))
                        else if (canEdit)
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => _run(
                                    () => _repository.setDefault(
                                      template,
                                      changedAt: _now,
                                    ),
                                  ),
                            child: Text(s.text('set_default')),
                          ),
                        if (canEdit)
                          IconButton(
                            tooltip: s.text('edit'),
                            onPressed: _busy ? null : () => _edit(template),
                            icon: const Icon(LucideIcons.pencil),
                          ),
                        if (role == 'owner')
                          IconButton(
                            tooltip: s.text('archive'),
                            onPressed: _busy
                                ? null
                                : () => _run(
                                    () => _repository.remove(
                                      template,
                                      changedAt: _now,
                                    ),
                                  ),
                            icon: const Icon(LucideIcons.archive),
                          ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
