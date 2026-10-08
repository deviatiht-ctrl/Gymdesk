import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/async_panel.dart';
import '../../../l10n/app_strings.dart';
import '../data/plans_repository.dart';
import '../domain/plan.dart';

class PlansPage extends ConsumerStatefulWidget {
  const PlansPage({super.key});
  @override
  ConsumerState<PlansPage> createState() => _PlansPageState();
}

class _PlansPageState extends ConsumerState<PlansPage> {
  late final PlansRepository _repository;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final runtime = ref.read(appRuntimeProvider);
    _repository = PlansRepository(runtime.database!, runtime.session!);
  }

  Future<void> _edit([GymPlan? plan]) async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final form = GlobalKey<FormState>();
    final fields = {
      'name': TextEditingController(text: plan?.name ?? ''),
      'duration_days': TextEditingController(
        text: '${plan?.durationDays ?? 30}',
      ),
      'price': TextEditingController(
        text: plan == null ? '' : plan.price.toStringAsFixed(2),
      ),
      'enrollment_price': TextEditingController(
        text: plan?.enrollmentPrice?.toStringAsFixed(2) ?? '',
      ),
      'description': TextEditingController(text: plan?.description ?? ''),
      'sort_order': TextEditingController(text: '${plan?.sortOrder ?? 0}'),
    };
    var active = plan?.active ?? true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(s.text(plan == null ? 'new_plan' : 'edit')),
          content: Form(
            key: form,
            child: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: fields['name'],
                      decoration: InputDecoration(
                        labelText: s.text('plan_name'),
                      ),
                      validator: (v) => (v?.trim().length ?? 0) < 2
                          ? s.text('invalid_record')
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: fields['duration_days'],
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: s.text('duration_days'),
                      ),
                      validator: (v) => (int.tryParse(v ?? '') ?? 0) < 1
                          ? s.text('invalid_record')
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: fields['price'],
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: s.text('renewal_price'),
                      ),
                      validator: (v) {
                        final amount = double.tryParse(
                          (v ?? '').replaceAll(',', '.'),
                        );
                        return amount == null || !amount.isFinite || amount < 0
                            ? s.text('invalid_record')
                            : null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: fields['enrollment_price'],
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: s.text('enrollment_price'),
                        helperText: s.text('enrollment_price_hint'),
                        helperMaxLines: 3,
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return null;
                        final amount = double.tryParse(v.replaceAll(',', '.'));
                        return amount == null || !amount.isFinite || amount < 0
                            ? s.text('invalid_record')
                            : null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: fields['sort_order'],
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: s.text('sort_order'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: fields['description'],
                      maxLength: 500,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: s.text('description'),
                        counterText: '',
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(s.text('active')),
                      value: active,
                      onChanged: (v) => setDialog(() => active = v),
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
      for (final field in fields.values) {
        field.dispose();
      }
      return;
    }
    setState(() => _busy = true);
    try {
      await _repository.save(
        PlanDraft(
          name: fields['name']!.text,
          durationDays: int.parse(fields['duration_days']!.text),
          price: double.parse(fields['price']!.text.replaceAll(',', '.')),
          enrollmentPrice: double.tryParse(
            fields['enrollment_price']!.text.replaceAll(',', '.'),
          ),
          currency:
              ref.read(appRuntimeProvider).session?.gym?['currency']
                  as String? ??
              'HTG',
          description: fields['description']!.text,
          active: active,
          sortOrder: int.tryParse(fields['sort_order']!.text) ?? 0,
        ),
        existing: plan,
        changedAt:
            ref.read(appRuntimeProvider).sync?.clock.correctedNow ??
            DateTime.now().toUtc(),
      );
      await ref.read(appRuntimeProvider).sync?.synchronize();
      await HapticFeedback.lightImpact();
    } on PlanFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.text(e.code))));
      }
    } finally {
      for (final field in fields.values) {
        field.dispose();
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _archive(GymPlan plan) async {
    if (_busy || ref.read(appRuntimeProvider).session?.role != 'owner') return;
    final s = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.text('archive')),
        content: Text(s.text('archive_plan_confirmation')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.text('archive')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await _repository.remove(
        plan,
        changedAt:
            ref.read(appRuntimeProvider).sync?.clock.correctedNow ??
            DateTime.now().toUtc(),
      );
      await ref.read(appRuntimeProvider).sync?.synchronize();
    } on PlanFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.text(e.code))));
      }
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
              Text(
                s.text('plans'),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              if (canEdit)
                FilledButton.icon(
                  onPressed: _busy ? null : () => _edit(),
                  icon: const Icon(LucideIcons.plus),
                  label: Text(s.text('new_plan')),
                ),
            ],
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
        Expanded(
          child: StreamBuilder<List<GymPlan>>(
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
                    message: s.text('plans_empty'),
                    action: canEdit ? s.text('new_plan') : null,
                    onAction: canEdit ? () => _edit() : null,
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: snapshot.data!.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final plan = snapshot.data![index];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    title: Text(plan.name),
                    subtitle: Text(
                      '${s.text('duration_days')}: ${plan.durationDays} · ${plan.price.toStringAsFixed(2)} ${plan.currency}${plan.description == null ? '' : '\n${plan.description}'}',
                    ),
                    trailing: Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(s.text(plan.active ? 'active' : 'inactive')),
                        if (canEdit)
                          IconButton(
                            tooltip: s.text('edit'),
                            onPressed: _busy ? null : () => _edit(plan),
                            icon: const Icon(LucideIcons.pencil),
                          ),
                        if (role == 'owner')
                          IconButton(
                            tooltip: s.text('archive'),
                            onPressed: _busy ? null : () => _archive(plan),
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
