import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/local_database.dart';
import '../../../core/sync/sync_models.dart';
import '../../payments/domain/payment.dart';
import '../../plans/domain/plan.dart';
import '../../subscriptions/domain/gym_subscription.dart';
import '../../subscriptions/domain/subscription_rules.dart';
import '../domain/member.dart';

class MemberListEntry {
  const MemberListEntry({
    required this.member,
    this.subscription,
    required this.validity,
  });
  final Member member;
  final GymSubscription? subscription;
  final MemberValidity validity;
}

class MembersRepository {
  const MembersRepository(this.client, this.db, this.session);
  final SupabaseClient client;
  final LocalDatabase db;
  final StaffSession session;
  static const _uuid = Uuid();

  Future<T> _local<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on MemberFailure {
      rethrow;
    } on SyncRejected catch (e) {
      throw MemberFailure(e.code);
    } catch (_) {
      throw const MemberFailure('local_storage');
    }
  }

  Stream<List<MemberListEntry>> watch({
    String query = '',
    String filter = 'all',
  }) {
    late StreamController<List<MemberListEntry>> controller;
    List<Member>? members;
    List<GymSubscription>? subscriptions;
    StreamSubscription<List<Record>>? memberRows;
    StreamSubscription<List<Record>>? subscriptionRows;
    void emit() {
      if (members == null || subscriptions == null || controller.isClosed) {
        return;
      }
      final byMember = <String, List<GymSubscription>>{};
      for (final subscription in subscriptions!) {
        byMember.putIfAbsent(subscription.memberId, () => []).add(subscription);
      }
      final text = query.trim().toLowerCase();
      final now = DateTime.now().toUtc();
      final result = members!
          .where((member) {
            if (text.isNotEmpty) {
              final haystack =
                  '${member.firstName} ${member.lastName} ${member.memberNumber} ${member.phone ?? ''} ${member.nif ?? ''}'
                      .toLowerCase();
              if (!haystack.contains(text)) return false;
            }
            final validity = memberValidity(
              member,
              byMember[member.id] ?? const [],
              session.settings,
              now,
              session.timezone,
            );
            return switch (filter) {
              'active' || 'suspended' || 'archived' => member.status == filter,
              'valid' => validity.valid,
              'expiring' => validity.valid && (validity.daysLeft ?? 0) <= 7,
              'expired' => validity.reason == 'expired',
              'pending' => validity.reason == 'pending_payment',
              'none' => validity.reason == 'no_subscription',
              _ => true,
            };
          })
          .map((member) {
            final current = _currentSubscription(
              byMember[member.id] ?? const [],
              now,
            );
            return MemberListEntry(
              member: member,
              subscription: current,
              validity: memberValidity(
                member,
                byMember[member.id] ?? const [],
                session.settings,
                now,
                session.timezone,
              ),
            );
          })
          .toList();
      result.sort(
        (a, b) =>
            a.member.lastName.toLowerCase() != b.member.lastName.toLowerCase()
            ? a.member.lastName.toLowerCase().compareTo(
                b.member.lastName.toLowerCase(),
              )
            : a.member.firstName.toLowerCase().compareTo(
                b.member.firstName.toLowerCase(),
              ),
      );
      controller.add(result);
    }

    controller = StreamController<List<MemberListEntry>>(
      onListen: () {
        memberRows = db.watchRecords(SyncEntity.members, limit: 50000).listen((
          rows,
        ) {
          members = rows
              .map(
                (row) => Member(
                  Map<String, dynamic>.from(jsonDecode(row.payload) as Map),
                ),
              )
              .toList();
          emit();
        }, onError: controller.addError);
        subscriptionRows = db
            .watchRecords(SyncEntity.subscriptions, limit: 50000)
            .listen((rows) {
              subscriptions = rows
                  .map(
                    (row) => GymSubscription(
                      Map<String, dynamic>.from(jsonDecode(row.payload) as Map),
                    ),
                  )
                  .toList();
              emit();
            }, onError: controller.addError);
      },
      onCancel: () async {
        await memberRows?.cancel();
        await subscriptionRows?.cancel();
      },
    );
    return controller.stream;
  }

  Stream<Member?> watchMember(String id) =>
      db.watchRecords(SyncEntity.members, limit: 50000).map((rows) {
        for (final row in rows) {
          if (row.id == id) {
            return Member(
              Map<String, dynamic>.from(jsonDecode(row.payload) as Map),
            );
          }
        }
        return null;
      });

  Stream<List<GymSubscription>> watchSubscriptions(String memberId) =>
      db.watchRecords(SyncEntity.subscriptions, limit: 50000).map((rows) {
        final subscriptions = rows
            .map(
              (row) => GymSubscription(
                Map<String, dynamic>.from(jsonDecode(row.payload) as Map),
              ),
            )
            .where((s) => s.memberId == memberId && s.deletedAt == null)
            .toList();
        subscriptions.sort((a, b) => b.endDate.compareTo(a.endDate));
        return subscriptions;
      });

  Stream<List<GymPayment>> watchPayments(String memberId) =>
      db.watchRecords(SyncEntity.payments, limit: 50000).map((rows) {
        final payments = rows
            .map(
              (row) => GymPayment(
                Map<String, dynamic>.from(jsonDecode(row.payload) as Map),
              ),
            )
            .where((p) => p.memberId == memberId && p.deletedAt == null)
            .toList();
        payments.sort((a, b) => b.paidAt.compareTo(a.paidAt));
        return payments;
      });

  Future<List<MemberDuplicate>> duplicates(
    MemberRegistration draft,
  ) => _local(() async {
    final nif = normalizeNif(draft.nif);
    final phone = normalizePhone(draft.phone);
    final whatsapp = normalizePhone(draft.whatsapp);
    final birth = draft.birthDate == null
        ? null
        : ymd(dateOnly(draft.birthDate!));
    final name = '${draft.firstName.trim()} ${draft.lastName.trim()}'
        .toLowerCase();
    final rows = await db.watchRecords(SyncEntity.members, limit: 50000).first;
    return rows
        .map(
          (row) =>
              Member(Map<String, dynamic>.from(jsonDecode(row.payload) as Map)),
        )
        .where((member) {
          if (nif != null && member.nif == nif) return true;
          if (phone.isNotEmpty &&
              (member.phone == phone || member.whatsapp == phone)) {
            return true;
          }
          if (whatsapp.isNotEmpty &&
              (member.phone == whatsapp || member.whatsapp == whatsapp)) {
            return true;
          }
          return birth != null &&
              member.birthDate != null &&
              ymd(member.birthDate!) == birth &&
              member.fullName.toLowerCase() == name;
        })
        .map(
          (member) => MemberDuplicate(
            member: member,
            reason: nif != null && member.nif == nif
                ? 'nif'
                : phone.isNotEmpty &&
                      (member.phone == phone || member.whatsapp == phone)
                ? 'phone'
                : whatsapp.isNotEmpty &&
                      (member.phone == whatsapp || member.whatsapp == whatsapp)
                ? 'phone'
                : 'name_birth',
          ),
        )
        .toList();
  });

  Future<MemberRegistrationResult> register(
    MemberRegistration draft, {
    SubscriptionCommand? subscription,
    PaymentCommand? payment,
    required DateTime changedAt,
  }) => _local(() async {
    _validateRegistration(draft);
    if (payment != null && subscription == null) {
      throw const MemberFailure('invalid_record');
    }
    if (payment != null && payment.amount > subscription!.price + 0.001) {
      throw const MemberFailure('invalid_record');
    }
    if (subscription != null) {
      _validateSubscription(subscription);
      final expected = (payment?.amount ?? 0) >= subscription.price - 0.001
          ? 'active'
          : 'pending';
      if (subscription.status != expected) {
        throw const MemberFailure('invalid_record');
      }
    }
    if (payment != null) _validatePayment(payment);
    final id = _uuid.v4();
    late String number;
    String? subscriptionId;
    String? paymentId;
    await db.transaction(() async {
      number = await db.nextMemberNumber();
      final memberRow = _memberRow(id, draft, number, changedAt);
      await db.save(SyncEntity.members, memberRow, changedAt: changedAt);
      if (draft.photo != null) await db.enqueuePhoto(id, draft.photo!);
      if (subscription != null) {
        subscriptionId = _uuid.v4();
        await db.save(
          SyncEntity.subscriptions,
          _subscriptionRow(subscriptionId!, id, subscription, changedAt),
          changedAt: changedAt,
        );
        if (payment != null && payment.amount > 0) {
          paymentId = _uuid.v4();
          await db.save(
            SyncEntity.payments,
            _paymentRow(
              paymentId!,
              payment.copyWith(memberId: id, subscriptionId: subscriptionId),
              changedAt,
            ),
            changedAt: changedAt,
          );
        }
      }
    });
    return MemberRegistrationResult(
      memberId: id,
      memberNumber: number,
      subscriptionId: subscriptionId,
      paymentId: paymentId,
    );
  });

  Future<void> updateProfile(
    Member member,
    MemberRegistration draft, {
    required DateTime changedAt,
  }) => _local(() async {
    if (!{'owner', 'supervisor', 'reception'}.contains(session.role)) {
      throw const MemberFailure('access_denied');
    }
    _validateRegistration(draft);
    await db.transaction(() async {
      await db.save(SyncEntity.members, {
        ...member.row,
        ..._memberRow(member.id, draft, member.memberNumber, changedAt),
        'id': member.id,
        'qr_token': member.qrToken,
        'status': member.status,
        'created_at': member.row['created_at'],
        'created_by': member.row['created_by'],
        'photo_url': member.photoUrl,
      }, changedAt: changedAt);
      if (draft.photo != null) await db.enqueuePhoto(member.id, draft.photo!);
    });
  });

  Future<void> changeStatus(
    Member member,
    String status, {
    required DateTime changedAt,
  }) => _local(() async {
    if (!{'owner', 'supervisor'}.contains(session.role) ||
        !{'active', 'suspended'}.contains(status)) {
      throw const MemberFailure('access_denied');
    }
    await db.save(SyncEntity.members, {
      ...member.row,
      'status': status,
    }, changedAt: changedAt);
  });

  Future<void> archive(Member member, {required DateTime changedAt}) =>
      _local(() async {
        if (session.role != 'owner') throw const MemberFailure('access_denied');
        await db.transaction(() async {
          await db.save(
            SyncEntity.members,
            member.row,
            changedAt: changedAt,
            deleting: true,
          );
          await (db.delete(
            db.photoUploads,
          )..where((t) => t.memberId.equals(member.id))).go();
        });
      });

  Future<GymSubscription> renew(
    Member member,
    GymPlan plan, {
    required DateTime start,
    required DateTime changedAt,
    PaymentCommand? payment,
  }) => _local(() async {
    if (!{'owner', 'supervisor', 'reception'}.contains(session.role)) {
      throw const MemberFailure('access_denied');
    }
    _validatePayment(payment);
    if (payment != null && payment.amount > plan.price + 0.001) {
      throw const MemberFailure('invalid_record');
    }
    final subscriptions = await db
        .watchRecords(SyncEntity.subscriptions, limit: 50000)
        .first
        .then(
          (rows) => rows
              .map(
                (row) => GymSubscription(
                  Map<String, dynamic>.from(jsonDecode(row.payload) as Map),
                ),
              )
              .where((s) => s.memberId == member.id && s.deletedAt == null)
              .toList(),
        );
    final today = gymDate(changedAt, session.timezone);
    final current =
        subscriptions
            .where((s) => s.status != 'cancelled' && !s.endDate.isBefore(today))
            .toList()
          ..sort((a, b) => b.endDate.compareTo(a.endDate));
    final startDate = current.isEmpty
        ? dateOnly(start)
        : current.first.endDate.add(const Duration(days: 1));
    final subscriptionId = _uuid.v4();
    final amount = payment?.amount ?? 0;
    final subscription = GymSubscription({
      'id': subscriptionId,
      'gym_id': session.gymId,
      'member_id': member.id,
      'plan_id': plan.id,
      'start_date': ymd(startDate),
      'end_date': ymd(subscriptionEnd(startDate, plan.durationDays)),
      'price': plan.price,
      'enrollment_kind': 'renewal',
      // La réception ne peut pas valider un renouvellement : il reste
      // 'pending' jusqu'à l'approbation d'un owner/supervisor.
      'status': amount >= plan.price && session.canManageGym
          ? 'active'
          : 'pending',
      'renewed_from': current.isEmpty ? null : current.first.id,
      'validated_by': amount >= plan.price && session.canManageGym
          ? session.staffId
          : null,
      'validated_at': amount >= plan.price && session.canManageGym
          ? changedAt.toUtc().toIso8601String()
          : null,
      'created_by': session.staffId,
      'created_at': changedAt.toUtc().toIso8601String(),
      'updated_at': changedAt.toUtc().toIso8601String(),
      'deleted_at': null,
    });
    await db.transaction(() async {
      await db.save(
        SyncEntity.subscriptions,
        subscription.row,
        changedAt: changedAt,
      );
      if (payment != null && payment.amount > 0) {
        await db.save(
          SyncEntity.payments,
          _paymentRow(
            _uuid.v4(),
            payment.copyWith(
              memberId: member.id,
              subscriptionId: subscriptionId,
            ),
            changedAt,
          ),
          changedAt: changedAt,
        );
      }
    });
    return subscription;
  });

  Future<void> collectPayment(
    GymSubscription subscription,
    PaymentCommand payment, {
    required DateTime changedAt,
  }) => _local(() async {
    if (!{'owner', 'supervisor', 'reception'}.contains(session.role)) {
      throw const MemberFailure('access_denied');
    }
    if (subscription.deletedAt != null || subscription.status == 'cancelled') {
      throw const MemberFailure('invalid_record');
    }
    _validatePayment(payment);
    final paidRows = await db
        .watchRecords(SyncEntity.payments, limit: 50000)
        .first;
    final paid = paidRows
        .map(
          (row) => GymPayment(
            Map<String, dynamic>.from(jsonDecode(row.payload) as Map),
          ),
        )
        .where(
          (p) => p.subscriptionId == subscription.id && p.deletedAt == null,
        )
        .fold<double>(0, (total, p) => total + p.amount);
    final remaining = subscription.remainingAfter(paid);
    if (payment.amount <= 0 || payment.amount > remaining + 0.001) {
      throw const MemberFailure('invalid_record');
    }
    await db.transaction(() async {
      await db.save(
        SyncEntity.payments,
        _paymentRow(
          _uuid.v4(),
          payment.copyWith(
            memberId: subscription.memberId,
            subscriptionId: subscription.id,
          ),
          changedAt,
        ),
        changedAt: changedAt,
      );
      if (subscription.status == 'pending' &&
          subscription.openingCredit + paid + payment.amount >=
              subscription.price - 0.001 &&
          session.canManageGym) {
        await db.save(SyncEntity.subscriptions, {
          ...subscription.row,
          'status': 'active',
        }, changedAt: changedAt);
      }
    });
  });

  Future<Uint8List?> localPhoto(String memberId) async =>
      (await db.photoForMember(memberId))?.bytes;

  Future<String?> signedPhotoUrl(String? path) async {
    if (path == null || path.isEmpty) return null;
    try {
      return await client.storage
          .from('member-photos')
          .createSignedUrl(path, 3600);
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> photoBytes(Member member) async {
    final local = await localPhoto(member.id);
    if (local != null) return local;
    if (member.photoUrl == null || member.photoUrl!.isEmpty) return null;
    try {
      return await client.storage
          .from('member-photos')
          .download(member.photoUrl!);
    } catch (_) {
      return null;
    }
  }

  GymSubscription? _currentSubscription(
    List<GymSubscription> subscriptions,
    DateTime now,
  ) {
    final date = gymDate(now, session.timezone);
    final usable =
        subscriptions
            .where((s) => s.deletedAt == null && s.status != 'cancelled')
            .toList()
          ..sort(
            (a, b) => a.endDate != b.endDate
                ? b.endDate.compareTo(a.endDate)
                : b.id.compareTo(a.id),
          );
    for (final subscription in usable) {
      if (!subscription.startDate.isAfter(date)) return subscription;
    }
    return usable.isEmpty ? null : usable.first;
  }

  void _validateRegistration(MemberRegistration draft) {
    if (draft.firstName.trim().length < 2 ||
        draft.lastName.trim().length < 2 ||
        draft.firstName.length > 80 ||
        draft.lastName.length > 80) {
      throw const MemberFailure('invalid_record');
    }
    if (draft.sex != null && !{'male', 'female', 'other'}.contains(draft.sex)) {
      throw const MemberFailure('invalid_record');
    }
    if (draft.birthDate != null &&
        draft.birthDate!.isAfter(dateOnly(DateTime.now()))) {
      throw const MemberFailure('invalid_record');
    }
    if (draft.birthDate != null &&
        (Member({
                  'id': 'x',
                  'gym_id': session.gymId,
                  'first_name': draft.firstName,
                  'last_name': draft.lastName,
                  'birth_date': ymd(draft.birthDate!),
                  'member_number': '',
                  'qr_token': '',
                  'status': 'active',
                  'updated_at': '',
                }).ageOn(dateOnly(DateTime.now())) ??
                18) <
            18 &&
        draft.guardianName.trim().isEmpty) {
      throw const MemberFailure('guardian_required');
    }
    if (draft.email.isNotEmpty &&
        (draft.email.length > 254 ||
            !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(draft.email))) {
      throw const MemberFailure('invalid_email');
    }
    if (draft.phone.length > 32 ||
        draft.whatsapp.length > 32 ||
        draft.emergencyPhone.length > 32 ||
        draft.address.length > 500 ||
        draft.notes.length > 1000 ||
        draft.cin.length > 50) {
      throw const MemberFailure('invalid_record');
    }
    if (normalizePhone(draft.phone).length > 32 ||
        normalizePhone(draft.whatsapp).length > 32 ||
        normalizePhone(draft.emergencyPhone).length > 32) {
      throw const MemberFailure('invalid_record');
    }
    normalizeNif(draft.nif);
  }

  void _validateSubscription(SubscriptionCommand command) {
    if (command.planId == null ||
        command.price < 0 ||
        command.endDate.isBefore(command.startDate) ||
        !{'active', 'pending'}.contains(command.status)) {
      throw const MemberFailure('invalid_record');
    }
  }

  void _validatePayment(PaymentCommand? payment) {
    if (payment == null) return;
    if (payment.amount < 0 ||
        payment.amount > 999999999 ||
        !{
          'cash',
          'moncash',
          'natcash',
          'bank',
          'other',
        }.contains(payment.method) ||
        !{'HTG', 'USD'}.contains(payment.currency) ||
        payment.reference.length > 120 ||
        payment.notes.length > 500) {
      throw const MemberFailure('invalid_record');
    }
  }

  Json _memberRow(
    String id,
    MemberRegistration draft,
    String number,
    DateTime changedAt,
  ) => {
    'id': id,
    'gym_id': session.gymId,
    'member_number': number,
    'qr_token': generateQrToken(),
    'first_name': draft.firstName.trim(),
    'last_name': draft.lastName.trim(),
    'sex': draft.sex,
    'birth_date': draft.birthDate == null
        ? null
        : ymd(dateOnly(draft.birthDate!)),
    'phone': normalizePhone(draft.phone).isEmpty
        ? null
        : normalizePhone(draft.phone),
    'whatsapp': normalizePhone(draft.whatsapp).isEmpty
        ? null
        : normalizePhone(draft.whatsapp),
    'email': draft.email.trim().isEmpty
        ? null
        : draft.email.trim().toLowerCase(),
    'address': draft.address.trim().isEmpty ? null : draft.address.trim(),
    'nif': normalizeNif(draft.nif),
    'cin': draft.cin.trim().isEmpty ? null : draft.cin.trim(),
    'emergency_contact_name': draft.emergencyName.trim().isEmpty
        ? null
        : draft.emergencyName.trim(),
    'emergency_contact_phone': normalizePhone(draft.emergencyPhone).isEmpty
        ? null
        : normalizePhone(draft.emergencyPhone),
    'guardian_name': draft.guardianName.trim().isEmpty
        ? null
        : draft.guardianName.trim(),
    'photo_url': null,
    'notes': draft.notes.trim().isEmpty ? null : draft.notes.trim(),
    'status': 'active',
    'qr_style': null,
    'created_by': session.staffId,
    'created_at': changedAt.toUtc().toIso8601String(),
    'updated_at': changedAt.toUtc().toIso8601String(),
    'deleted_at': null,
  };

  Json _subscriptionRow(
    String id,
    String memberId,
    SubscriptionCommand command,
    DateTime changedAt,
  ) => {
    'id': id,
    'gym_id': session.gymId,
    'member_id': memberId,
    'plan_id': command.planId,
    'start_date': ymd(dateOnly(command.startDate)),
    'end_date': ymd(dateOnly(command.endDate)),
    'price': command.price,
    'status': command.status,
    'renewed_from': command.renewedFrom,
    'created_by': session.staffId,
    'created_at': changedAt.toUtc().toIso8601String(),
    'updated_at': changedAt.toUtc().toIso8601String(),
    'deleted_at': null,
  };

  Json _paymentRow(String id, PaymentCommand command, DateTime changedAt) => {
    'id': id,
    'gym_id': session.gymId,
    'member_id': command.memberId,
    'subscription_id': command.subscriptionId,
    'amount': command.amount,
    'currency': command.currency,
    'method': command.method,
    'reference': command.reference.trim().isEmpty
        ? null
        : command.reference.trim(),
    'paid_at': changedAt.toUtc().toIso8601String(),
    'received_by': session.staffId,
    'notes': command.notes.trim().isEmpty ? null : command.notes.trim(),
    'created_at': changedAt.toUtc().toIso8601String(),
    'updated_at': changedAt.toUtc().toIso8601String(),
    'deleted_at': null,
  };
}
