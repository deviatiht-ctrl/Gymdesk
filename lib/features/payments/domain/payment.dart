import '../../../core/sync/sync_models.dart';

class GymPayment {
  const GymPayment(this.row);
  final Json row;

  String get id => row['id'] as String;
  String get gymId => row['gym_id'] as String;
  String get memberId => row['member_id'] as String;
  String? get subscriptionId => row['subscription_id'] as String?;
  double get amount => (row['amount'] as num?)?.toDouble() ?? 0;
  String get currency => row['currency'] as String? ?? 'HTG';
  String get method => row['method'] as String? ?? 'cash';
  String? get reference => row['reference'] as String?;
  DateTime get paidAt => DateTime.parse(row['paid_at'] as String);
  String? get receivedBy => row['received_by'] as String?;
  String? get notes => row['notes'] as String?;
  String get updatedAt => row['updated_at'] as String;
  String? get deletedAt => row['deleted_at'] as String?;
}

class PaymentCommand {
  const PaymentCommand({
    required this.memberId,
    this.subscriptionId,
    required this.amount,
    this.currency = 'HTG',
    required this.method,
    this.reference = '',
    this.notes = '',
  });
  final String memberId;
  final String? subscriptionId;
  final double amount;
  final String currency;
  final String method;
  final String reference;
  final String notes;
}

extension PaymentCommandCopy on PaymentCommand {
  PaymentCommand copyWith({String? memberId, Object? subscriptionId = _same}) =>
      PaymentCommand(
        memberId: memberId ?? this.memberId,
        subscriptionId: identical(subscriptionId, _same)
            ? this.subscriptionId
            : subscriptionId as String?,
        amount: amount,
        currency: currency,
        method: method,
        reference: reference,
        notes: notes,
      );
  static const _same = Object();
}

class PaymentFailure implements Exception {
  const PaymentFailure(this.code);
  final String code;
}
