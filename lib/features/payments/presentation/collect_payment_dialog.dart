import 'package:flutter/material.dart';

import '../../../l10n/app_strings.dart';
import '../domain/payment.dart';

/// Rezilta dyalòg peman an — tout chan resi/balans yo.
class CollectResult {
  const CollectResult({
    required this.amount,
    required this.received,
    required this.method,
    this.creditUsed = 0,
    this.keepChangeAsCredit = false,
  });

  /// Montan aplike sou abònman an.
  final double amount;

  /// Lajan kliyan an bay nan men (kach).
  final double received;
  final String method;

  /// Pati peye ak balans manm nan.
  final double creditUsed;

  /// Si rès la rete kòm kredi sou kont manm nan.
  final bool keepChangeAsCredit;

  PaymentCommand command({String? id, required String memberId, String? subscriptionId, String currency = 'HTG'}) =>
      PaymentCommand(
        id: id,
        memberId: memberId,
        subscriptionId: subscriptionId,
        amount: amount,
        currency: currency,
        method: method,
        receivedAmount: received,
        creditUsed: creditUsed,
        keepChangeAsCredit: keepChangeAsCredit,
      );
}

/// Dyalòg peman pataje: montan, montan resi, metòd, balans, rès→kredi.
/// [due] = sa ki rete pou peye. [balance] = kredi manm nan.
Future<CollectResult?> showCollectPaymentDialog(
  BuildContext context, {
  required String title,
  required double due,
  required double balance,
  double? fixedAmount,
}) {
  final s = AppStrings.of(context);
  final amount = TextEditingController(
    text: (fixedAmount ?? due).toStringAsFixed(2),
  );
  final received = TextEditingController();
  String method = 'cash';
  var creditUsed = 0.0;
  var keepCredit = false;
  return showDialog<CollectResult>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialog) {
        final applied = double.tryParse(amount.text.replaceAll(',', '.')) ?? 0;
        final cashDue = applied - creditUsed;
        final got = double.tryParse(received.text.replaceAll(',', '.'));
        final rest = (got ?? cashDue) - cashDue;
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: amount,
                  readOnly: fixedAmount != null,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(labelText: s.text('amount')),
                  onChanged: (_) => setDialog(() {}),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: received,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: s.text('amount_received'),
                    hintText: cashDue.toStringAsFixed(2),
                  ),
                  onChanged: (_) => setDialog(() {}),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: method,
                  decoration: InputDecoration(
                    labelText: s.text('payment_method'),
                  ),
                  items: ['cash', 'moncash', 'natcash', 'bank', 'other']
                      .map(
                        (m) => DropdownMenuItem(
                          value: m,
                          child: Text(s.text('method_$m')),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => method = v ?? 'cash',
                ),
                if (balance > 0)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(s.text('use_balance')),
                    subtitle: Text(
                      '${s.text('balance_available')}: ${balance.toStringAsFixed(2)}',
                    ),
                    value: creditUsed > 0,
                    onChanged: (v) => setDialog(
                      () => creditUsed = v == true
                          ? (balance < applied ? balance : applied)
                          : 0,
                    ),
                  ),
                if (rest > 0.004)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(s.text('keep_change_as_credit')),
                    subtitle: Text('+${rest.toStringAsFixed(2)}'),
                    value: keepCredit,
                    onChanged: (v) => setDialog(() => keepCredit = v == true),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    s.text('receipt_auto_email_hint'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s.text('cancel')),
            ),
            FilledButton(
              onPressed: applied <= 0
                  ? null
                  : () => Navigator.pop(
                      context,
                      CollectResult(
                        amount: applied,
                        received: got ?? cashDue,
                        method: method,
                        creditUsed: creditUsed,
                        keepChangeAsCredit: keepCredit,
                      ),
                    ),
              child: Text(s.text('save')),
            ),
          ],
        );
      },
    ),
  ).whenComplete(() {
    amount.dispose();
    received.dispose();
  });
}
