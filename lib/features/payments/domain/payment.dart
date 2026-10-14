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
  double get receivedAmount =>
      (row['received_amount'] as num?)?.toDouble() ?? amount - creditUsed;
  double get creditUsed => (row['credit_used'] as num?)?.toDouble() ?? 0;
  double get creditAmount => (row['credit_amount'] as num?)?.toDouble() ?? 0;
  double get cashDue => amount - creditUsed;
  double get changeReturned =>
      (receivedAmount - cashDue - creditAmount).clamp(0, double.infinity);
  DateTime get paidAt => DateTime.parse(row['paid_at'] as String);
  String? get receivedBy => row['received_by'] as String?;
  String? get notes => row['notes'] as String?;
  String get updatedAt => row['updated_at'] as String;
  String? get deletedAt => row['deleted_at'] as String?;
}

class PaymentCommand {
  const PaymentCommand({
    this.id,
    required this.memberId,
    this.subscriptionId,
    required this.amount,
    this.currency = 'HTG',
    required this.method,
    this.reference = '',
    this.notes = '',
    this.receivedAmount,
    this.creditUsed = 0,
    this.keepChangeAsCredit = false,
  });
  /// ID peman an — relevè a ka jenere l davans pou resi/storage. Null = repo jenere.
  final String? id;
  final String memberId;
  final String? subscriptionId;
  final double amount;
  final String currency;
  final String method;
  final String reference;
  final String notes;

  /// Lajan kliyan an reyèlman bay nan men. Null = egzak nan sa l dwe peye a.
  final double? receivedAmount;

  /// Pati nan [amount] ki peye ak balans manm nan (kredi anrejistre).
  final double creditUsed;

  /// Si vre, rès kòb la (received - cashDue) vin yon kredi sou kont manm nan
  /// olye l tounen kòm monney.
  final bool keepChangeAsCredit;

  double get cashDue => amount - creditUsed;
  double get effectiveReceived => receivedAmount ?? cashDue;
  double get changeDue => effectiveReceived - cashDue;
  double get creditAdded => keepChangeAsCredit ? changeDue : 0;
  double get changeReturned => keepChangeAsCredit ? 0 : changeDue;
}

extension PaymentCommandCopy on PaymentCommand {
  PaymentCommand copyWith({String? memberId, Object? subscriptionId = _same}) =>
      PaymentCommand(
        id: id,
        memberId: memberId ?? this.memberId,
        subscriptionId: identical(subscriptionId, _same)
            ? this.subscriptionId
            : subscriptionId as String?,
        amount: amount,
        currency: currency,
        method: method,
        reference: reference,
        notes: notes,
        receivedAmount: receivedAmount,
        creditUsed: creditUsed,
        keepChangeAsCredit: keepChangeAsCredit,
      );
  static const _same = Object();
}

class PaymentFailure implements Exception {
  const PaymentFailure(this.code);
  final String code;
}
