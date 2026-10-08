import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/db/local_database.dart';
import '../../../core/widgets/async_panel.dart';
import '../../../l10n/app_strings.dart';

class SyncPage extends ConsumerWidget {
  const SyncPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runtime = ref.watch(appRuntimeProvider);
    final s = AppStrings.of(context);
    return ListenableBuilder(
      listenable: runtime,
      builder: (context, _) {
        final engine = runtime.sync;
        final db = runtime.database;
        if (engine == null || db == null) {
          return MessagePanel(message: s.text('platform_hint'));
        }
        final state = engine.state.value;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              s.text('sync'),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                Text('${s.text('pending')}: ${state.pending}'),
                Text('${s.text('failed')}: ${state.failed}'),
                Text('${s.text('conflicts')}: ${state.conflicts}'),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '${s.text('last_sync')}: ${state.lastSync?.toLocal().toString().split('.').first ?? s.text('never')}',
            ),
            if (state.errorCode != null)
              MessagePanel(message: s.text(state.errorCode!)),
            if (state.clockSuspect)
              MessagePanel(message: s.text('clock_warning')),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton(
                  onPressed: () => engine.synchronize(retry: true),
                  child: Text(s.text('retry_all')),
                ),
                OutlinedButton(
                  onPressed: () => engine.synchronize(full: true),
                  child: Text(s.text('sync_full')),
                ),
                if (runtime.session?.canManageGym == true)
                  OutlinedButton(
                    onPressed: () async {
                      try {
                        final result = await runtime.client.rpc(
                          'email_delivery_status',
                        );
                        final counts = Map<String, dynamic>.from(
                          result['counts'] as Map,
                        );
                        if (!context.mounted) return;
                        await showDialog<void>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: Text(s.text('email_delivery')),
                            content: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${s.text('email_daily_limit')}: ${result['daily_limit']}',
                                  ),
                                  const SizedBox(height: 12),
                                  for (final status in [
                                    'pending',
                                    'sending',
                                    'sent',
                                    'failed',
                                    'uncertain',
                                  ])
                                    Text(
                                      '${s.text('email_$status')}: ${counts[status] ?? 0}',
                                    ),
                                  const SizedBox(height: 12),
                                  Text(s.text('email_queue_hint')),
                                  if (result['paused_until'] != null)
                                    Text(
                                      '${s.text('email_pause_until')}: ${result['paused_until']}',
                                    ),
                                ],
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dialogContext),
                                child: Text(s.text('done')),
                              ),
                            ],
                          ),
                        );
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(s.text('email_status_unavailable')),
                            ),
                          );
                        }
                      }
                    },
                    child: Text(s.text('email_delivery')),
                  ),
              ],
            ),
            const SizedBox(height: 32),
            Text(
              s.text('pending'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            StreamBuilder<List<OutboxData>>(
              stream: db.watchQueue(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return MessagePanel(message: s.text('local_storage'));
                }
                if (!snapshot.hasData) return const LoadingPanel(rows: 3);
                if (snapshot.data!.isEmpty) {
                  return MessagePanel(message: s.text('queue_empty'));
                }
                return Column(
                  children: snapshot.data!
                      .map(
                        (op) => ListTile(
                          title: Text(
                            '${s.text(op.entity)} · ${s.text(op.operation)}',
                          ),
                          subtitle: Text(
                            op.lastError == null
                                ? s.text('pending')
                                : s.text(op.lastError!),
                          ),
                          trailing: Text(op.attempts.toString()),
                        ),
                      )
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 32),
            Text(
              s.text('photos'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            StreamBuilder<List<PhotoUpload>>(
              stream: db.select(db.photoUploads).watch(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return MessagePanel(message: s.text('local_storage'));
                }
                if (!snapshot.hasData) return const LoadingPanel(rows: 1);
                return Column(
                  children: snapshot.data!
                      .map(
                        (photo) => ListTile(
                          title: Text(s.text('photos')),
                          subtitle: Text(s.text(photo.lastError ?? 'pending')),
                          trailing: Text(photo.attempts.toString()),
                        ),
                      )
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 32),
            Text(
              s.text('conflicts'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            StreamBuilder<List<SyncConflict>>(
              stream: db.watchConflicts(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return MessagePanel(message: s.text('local_storage'));
                }
                if (!snapshot.hasData) return const LoadingPanel(rows: 2);
                if (snapshot.data!.isEmpty) {
                  return MessagePanel(message: s.text('conflicts_empty'));
                }
                return Column(
                  children: snapshot.data!
                      .map(
                        (conflict) => ListTile(
                          title: Text(
                            '${s.text(conflict.entity)} · ${conflict.entityId}',
                          ),
                          subtitle: Text(s.text('conflict_hint')),
                          trailing: TextButton(
                            onPressed: () async {
                              try {
                                await (db.update(db.syncConflicts)
                                      ..where((t) => t.id.equals(conflict.id)))
                                    .write(
                                      const SyncConflictsCompanion(
                                        reviewed: Value(1),
                                      ),
                                    );
                              } catch (_) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(s.text('local_storage')),
                                    ),
                                  );
                                }
                              }
                            },
                            child: Text(s.text('reviewed')),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        );
      },
    );
  }
}
