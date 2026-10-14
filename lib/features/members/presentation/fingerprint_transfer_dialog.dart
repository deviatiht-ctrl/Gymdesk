import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/providers.dart';
import '../../../core/access_control/terminal_access_service.dart';
import '../../../core/biometrics/access_agent_client.dart';
import '../../../core/sync/sync_models.dart';
import '../data/members_repository.dart';
import '../domain/member.dart';

class FingerprintTransferDialog extends ConsumerStatefulWidget {
  const FingerprintTransferDialog({
    super.key,
    required this.entries,
    required this.onDone,
  });

  final List<MemberListEntry> entries;
  final VoidCallback onDone;

  static Future<void> show(
    BuildContext context, {
    required List<MemberListEntry> entries,
    required VoidCallback onDone,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FingerprintTransferDialog(entries: entries, onDone: onDone),
    );
  }

  @override
  ConsumerState<FingerprintTransferDialog> createState() => _FingerprintTransferDialogState();
}

class _FingerprintTransferDialogState extends ConsumerState<FingerprintTransferDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final TextEditingController _terminalIpCtrl;
  final TextEditingController _importDataCtrl = TextEditingController();

  bool _isSyncingTerminal = false;
  TerminalSyncResult? _lastSyncResult;
  String? _syncErrorMessage;

  bool _isImporting = false;
  int _importedCount = 0;
  int _unmatchedCount = 0;
  List<String> _importErrors = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    final runtime = ref.read(appRuntimeProvider);
    final localCfg = runtime.session?.settings['biometric_config'] as Map?;
    final ip = (localCfg?['terminal_ip'] as String?)?.trim();
    _terminalIpCtrl = TextEditingController(text: ip?.isNotEmpty == true ? ip! : '192.168.1.41');
  }

  @override
  void dispose() {
    _tabController.dispose();
    _terminalIpCtrl.dispose();
    _importDataCtrl.dispose();
    super.dispose();
  }

  int get _withFingerprintCount =>
      widget.entries.where((e) => e.member.fingerprintRegistered).length;
  int get _withoutFingerprintCount =>
      widget.entries.where((e) => !e.member.fingerprintRegistered).length;

  Future<void> _pushToTerminal() async {
    setState(() {
      _isSyncingTerminal = true;
      _lastSyncResult = null;
      _syncErrorMessage = null;
    });

    try {
      final runtime = ref.read(appRuntimeProvider);
      final client = runtime.client;
      final session = runtime.session!;
      final db = runtime.database!;

      final baseCfg = await TerminalAccessService.loadConfig(client, session);
      final effectiveCfg = TerminalAccessConfig(
        terminalEnforces: baseCfg.terminalEnforces,
        appControls: baseCfg.appControls,
        terminalIp: _terminalIpCtrl.text.trim().isNotEmpty
            ? _terminalIpCtrl.text.trim()
            : baseCfg.terminalIp,
        pulseSeconds: baseCfg.pulseSeconds,
      );

      final service = TerminalAccessService(client, db, session);
      final result = await service.syncToTerminal(effectiveCfg);

      if (mounted) {
        setState(() {
          _lastSyncResult = result;
          _isSyncingTerminal = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _syncErrorMessage = e.toString();
          _isSyncingTerminal = false;
        });
      }
    }
  }

  Future<void> _autoDiscoverTerminal() async {
    setState(() => _isSyncingTerminal = true);
    final client = AccessAgentClient();
    final devices = await client.searchTerminals();
    if (!mounted) return;
    setState(() => _isSyncingTerminal = false);
    if (devices.isNotEmpty) {
      final ip = devices.first['ip']?.toString();
      if (ip != null && ip.isNotEmpty) {
        setState(() => _terminalIpCtrl.text = ip);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Tèminal BioEntry W2 jwenn sou adrès IP: $ip !'),
            backgroundColor: const Color(0xFF059669),
          ),
        );
        return;
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Okenn tèminal pa jwenn otomatikman sou rezo a.'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  Future<void> _importLegacyFingerprints() async {
    final text = _importDataCtrl.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _isImporting = true;
      _importedCount = 0;
      _unmatchedCount = 0;
      _importErrors = [];
    });

    try {
      final runtime = ref.read(appRuntimeProvider);
      final client = runtime.client;
      final db = runtime.database;
      final now = runtime.sync?.clock.correctedNow ?? DateTime.now().toUtc();

      final membersById = <String, Member>{};
      final membersByNum = <String, Member>{};
      final membersByPhone = <String, Member>{};
      final membersByName = <String, Member>{};

      for (final e in widget.entries) {
        final m = e.member;
        membersById[m.id.replaceAll('-', '').toLowerCase()] = m;
        membersById[m.id.toLowerCase()] = m;
        if (m.memberNumber.isNotEmpty) {
          membersByNum[m.memberNumber.trim().toLowerCase()] = m;
        }
        if (m.phone?.isNotEmpty == true) {
          final cleanPhone = m.phone!.replaceAll(RegExp(r'\D'), '');
          membersByPhone[cleanPhone] = m;
          membersByPhone[m.phone!.trim()] = m;
        }
        final nameKey = '${m.firstName} ${m.lastName}'.trim().toLowerCase();
        if (nameKey.isNotEmpty) {
          membersByName[nameKey] = m;
        }
      }

      final extracted = <String, String>{};

      final lines = const LineSplitter().convert(text);
      for (final rawLine in lines) {
        final line = rawLine.trim();
        if (line.isEmpty) continue;

        if (line.startsWith('finger\t') || line.contains('\tfinger\t')) {
          final parts = line.split('\t');
          if (parts.length >= 4) {
            final uid = parts[1].trim();
            final tpl = parts[3].trim();
            if (uid.isNotEmpty && tpl.isNotEmpty) {
              extracted[uid] = tpl;
            }
          }
          continue;
        }

        if (line.contains('\t')) {
          final parts = line.split('\t');
          if (parts.length >= 2) {
            final id = parts[0].trim();
            final tpl = parts[1].trim();
            if (id.isNotEmpty && tpl.length > 50) {
              extracted[id] = tpl;
              continue;
            }
          }
        }

        if (line.contains(',')) {
          final parts = line.split(',');
          if (parts.length >= 2) {
            final id = parts[0].trim();
            final tpl = parts[1].trim();
            if (id.isNotEmpty && tpl.length > 50) {
              extracted[id] = tpl;
              continue;
            }
          }
        }
      }

      var success = 0;
      var unmatched = 0;
      final errors = <String>[];

      for (final item in extracted.entries) {
        final rawKey = item.key.trim();
        final template = item.value.trim();

        Member? target = membersById[rawKey.replaceAll('-', '').toLowerCase()] ??
            membersById[rawKey.toLowerCase()] ??
            membersByNum[rawKey.toLowerCase()] ??
            membersByPhone[rawKey.replaceAll(RegExp(r'\D'), '')] ??
            membersByName[rawKey.toLowerCase()];

        if (target == null) {
          unmatched++;
          continue;
        }

        try {
          await client.from('members').update({
            'fingerprint_template': template,
            'fingerprint_registered': true,
            'updated_at': now.toIso8601String(),
          }).eq('id', target.id).timeout(const Duration(seconds: 5));

          if (db != null) {
            final updatedRow = {
              ...target.row,
              'fingerprint_template': template,
              'fingerprint_registered': true,
              'updated_at': now.toIso8601String(),
            };
            await db.save(SyncEntity.members, updatedRow, changedAt: now);
          }
          success++;
        } catch (e) {
          errors.add('${target.fullName}: $e');
        }
      }

      unawaited(runtime.sync?.synchronize());
      widget.onDone();

      if (mounted) {
        setState(() {
          _isImporting = false;
          _importedCount = success;
          _unmatchedCount = unmatched;
          _importErrors = errors;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isImporting = false;
          _importErrors = [e.toString()];
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: const Color(0xFF0F172A),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F766E).withAlpha(60),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF14B8A6).withAlpha(120)),
                    ),
                    child: const Icon(LucideIcons.fingerprint, color: Color(0xFF2DD4BF), size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Transfè & Senkronizasyon Anprent',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Pouse anprent yo sou BioEntry W2 oswa enpòte ansyen anprent BioStar 2.',
                          style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x, color: Colors.white70),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _statItem('Total Manm', '${widget.entries.length}', LucideIcons.users, Colors.white70),
                    Container(height: 32, width: 1, color: Colors.white12),
                    _statItem('Ak Anprent', '$_withFingerprintCount', LucideIcons.fingerprint, const Color(0xFF10B981)),
                    Container(height: 32, width: 1, color: Colors.white12),
                    _statItem('San Anprent', '$_withoutFingerprintCount', LucideIcons.userX, const Color(0xFFF59E0B)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TabBar(
                controller: _tabController,
                indicatorColor: const Color(0xFF14B8A6),
                indicatorWeight: 3,
                labelColor: const Color(0xFF2DD4BF),
                unselectedLabelColor: Colors.white60,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                tabs: const [
                  Tab(icon: Icon(LucideIcons.uploadCloud, size: 18), text: 'Pouse sou Tèminal (W2)'),
                  Tab(icon: Icon(LucideIcons.folderDown, size: 18), text: 'Enpòte Ansyen Anprent (BioStar 2)'),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildTerminalSyncTab(),
                    _buildLegacyImportTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statItem(String label, String value, IconData icon, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: TextStyle(color: color, fontSize: 17, fontWeight: FontWeight.bold)),
            Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ],
        ),
      ],
    );
  }

  Widget _buildTerminalSyncTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0F766E).withAlpha(30),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF14B8A6).withAlpha(60)),
            ),
            child: const Text(
              'Aksyon sa a ap voye tout anprent ak dat ekspirasyon manm ki an règ yo dirèkteman sou tèminal Suprema BioEntry W2 devan pòt la. Pòt la ap ka ouvri otomatikman menm si laptop la etenn.',
              style: TextStyle(color: Color(0xFFCCFBF1), fontSize: 13, height: 1.4),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _terminalIpCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Adrès IP Tèminal W2 a',
                    prefixIcon: Icon(LucideIcons.network, color: Color(0xFF14B8A6), size: 18),
                    filled: true,
                    fillColor: Color(0xFF1E293B),
                    border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF2DD4BF),
                  side: const BorderSide(color: Color(0xFF14B8A6)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
                ),
                onPressed: _isSyncingTerminal ? null : _autoDiscoverTerminal,
                icon: const Icon(LucideIcons.scanLine, size: 18),
                label: const Text('Chèche IP'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _isSyncingTerminal ? null : _pushToTerminal,
            icon: _isSyncingTerminal
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(LucideIcons.arrowUpRight),
            label: Text(
              _isSyncingTerminal
                  ? 'Senkronizasyon ap fèt ak Tèminal la...'
                  : 'Pouse $_withFingerprintCount Anprent sou Tèminal la Kounye a',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
          if (_syncErrorMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red.withAlpha(40),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withAlpha(120)),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.alertTriangle, color: Colors.redAccent, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Erè pandan senkronizasyon: $_syncErrorMessage\nAsire w ke access_agent.exe ap kouri sou laptop la epi tèminal la sou menm rezo a.',
                      style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_lastSyncResult != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _lastSyncResult!.ok
                    ? const Color(0xFF059669).withAlpha(40)
                    : Colors.orange.withAlpha(40),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _lastSyncResult!.ok
                      ? const Color(0xFF10B981).withAlpha(120)
                      : Colors.orange.withAlpha(120),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _lastSyncResult!.ok ? LucideIcons.checkCircle2 : LucideIcons.alertCircle,
                        color: _lastSyncResult!.ok ? const Color(0xFF10B981) : Colors.orangeAccent,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _lastSyncResult!.ok ? 'Senkronizasyon Reyisi !' : 'Avètisman Senkronizasyon',
                        style: TextStyle(
                          color: _lastSyncResult!.ok ? const Color(0xFF6EE7B7) : Colors.orangeAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• Anprent enskri sou W2: ${_lastSyncResult!.enrolled}\n'
                    '• Ansyen itilizatè retire: ${_lastSyncResult!.removed}\n'
                    '• Moun ki sote: ${_lastSyncResult!.skipped}\n'
                    '• Manm san anprent: ${_lastSyncResult!.withoutFingerprint}',
                    style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.5),
                  ),
                  if (_lastSyncResult!.errors.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Erè tèminal: ${_lastSyncResult!.errors.join(", ")}',
                      style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLegacyImportTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: const Text(
              'Kole done ekspòtasyon BioStar 2 oswa fichye backup anprent ou anba a.\n'
              'Sistèm nan ap detekte manm yo otomatikman pa Nimewo Manm, Nimewo Telefòn, ID, oswa Non.',
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _importDataCtrl,
            maxLines: 6,
            style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 12),
            decoration: const InputDecoration(
              hintText: 'finger\t1001\t0\tAQIDBAUG...\n'
                  'Oswa CSV: 1001,AQIDBAUG...\n'
                  'Oswa: +50937123456,AQIDBAUG...',
              hintStyle: TextStyle(color: Colors.white24),
              filled: true,
              fillColor: Color(0xFF1E293B),
              border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
            ),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _isImporting ? null : _importLegacyFingerprints,
            icon: _isImporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(LucideIcons.fileCheck),
            label: Text(
              _isImporting
                  ? 'Analiz & Enpòtasyon ap fèt...'
                  : 'Analize & Enpòte nan SecurGYM',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
          if (_importedCount > 0 || _unmatchedCount > 0 || _importErrors.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF6366F1).withAlpha(120)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(LucideIcons.checkCircle2, color: Color(0xFF818CF8), size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Rezilta Enpòtasyon: $_importedCount anprent asosye avèk siksè !',
                        style: const TextStyle(
                          color: Color(0xFFA5B4FC),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  if (_unmatchedCount > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      '• $_unmatchedCount anprent pa jwenn okenn manm korespondan nan lis la.',
                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ],
                  if (_importErrors.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Erè: ${_importErrors.join(", ")}',
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                    ),
                  ],
                  if (_importedCount > 0) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF2DD4BF),
                        side: const BorderSide(color: Color(0xFF2DD4BF)),
                      ),
                      onPressed: () {
                        _tabController.animateTo(0);
                        _pushToTerminal();
                      },
                      icon: const Icon(LucideIcons.arrowUpRight, size: 16),
                      label: const Text('Pouse yo sou Tèminal la Kounye a'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
