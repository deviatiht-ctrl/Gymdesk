import 'package:flutter/material.dart';

import '../../../l10n/app_strings.dart';
import '../domain/currency.dart';
import '../domain/payment.dart';

/// Rezilta dyalòg peman an — tout chan resi/balans yo.
class CollectResult {
  const CollectResult({
    required this.amount,
    required this.received,
    required this.method,
    this.creditUsed = 0,
    this.keepChangeAsCredit = false,
    this.paidCurrency,
    this.exchangeRate,
    this.tendered,
  });

  /// Montan aplike sou abònman an (deviz plan an).
  final double amount;

  /// Lajan kliyan an bay nan men, konvèti nan deviz plan an.
  final double received;
  final String method;

  /// Pati peye ak balans manm nan.
  final double creditUsed;

  /// Si rès la rete kòm kredi sou kont manm nan.
  final bool keepChangeAsCredit;

  /// Deviz kliyan an peye a (USD oswa HTG) + to a + kòb li bay nan deviz sa a.
  final String? paidCurrency;
  final double? exchangeRate;
  final double? tendered;

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
        paidCurrency: paidCurrency ?? currency,
        exchangeRate: exchangeRate,
        tenderedAmount: tendered,
      );
}

/// Calcule ce que le caissier voit : dû dans la devise payée, monnaie, et le
/// montant reçu ramené dans la devise du plan (pour la logique de solde).
class CashierMath {
  const CashierMath({
    required this.currency,
    required this.paidCurrency,
    required this.rate,
    required this.cashDue,
    this.tendered,
  });
  final String currency;
  final String paidCurrency;
  final double rate;
  final double cashDue;
  final double? tendered;

  double get dueInPaid => round2(convertCurrency(cashDue, currency, paidCurrency, rate));
  double get given => tendered ?? dueInPaid;
  bool get enough => given >= dueInPaid - 0.004;
  double get changeInPaid => (given - dueInPaid).clamp(0, double.infinity).toDouble();

  /// Reçu ramené dans la devise du plan, jamais sous le dû à cause d'un arrondi.
  double get receivedInBase {
    if (!enough) return round2(convertCurrency(given, paidCurrency, currency, rate));
    return cashDue + round2(convertCurrency(changeInPaid, paidCurrency, currency, rate));
  }
}

/// Dyalòg peman pataje: montan, deviz peye (USD/HTG + to), montan resi,
/// metòd, balans, rès→kredi. [due] = sa ki rete pou peye (deviz [currency]).
Future<CollectResult?> showCollectPaymentDialog(
  BuildContext context, {
  required String title,
  required double due,
  required double balance,
  double? fixedAmount,
  String currency = 'HTG',
  double rate = 0,
}) {
  final s = AppStrings.of(context);
  final amount = TextEditingController(
    text: (fixedAmount ?? due).toStringAsFixed(2),
  );
  final received = TextEditingController();
  String method = 'cash';
  var paidCurrency = currency;
  var creditUsed = 0.0;
  var keepCredit = false;
  return showDialog<CollectResult>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialog) {
        final applied = double.tryParse(amount.text.replaceAll(',', '.')) ?? 0;
        final math = CashierMath(
          currency: currency,
          paidCurrency: paidCurrency,
          rate: rate,
          cashDue: applied - creditUsed,
          tendered: double.tryParse(received.text.replaceAll(',', '.')),
        );
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: amount,
                    readOnly: fixedAmount != null,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: '${s.text('amount')} ($currency)'),
                    onChanged: (_) => setDialog(() {}),
                  ),
                  if (rate > 0) ...[
                    const SizedBox(height: 14),
                    Text(s.text('paid_in_currency'), style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 6),
                    SegmentedButton<String>(
                      segments: [
                        for (final c in supportedCurrencies) ButtonSegment(value: c, label: Text(c)),
                      ],
                      selected: {paidCurrency},
                      onSelectionChanged: (v) => setDialog(() {
                        paidCurrency = v.first;
                        received.clear();
                      }),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${s.text('amount_due')}: ${money(math.dueInPaid, paidCurrency)}'
                      '  ·  ${s.text('exchange_rate')}: 1 USD = ${rate.toStringAsFixed(2)} HTG',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: received,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: '${s.text('amount_received')} ($paidCurrency)',
                      hintText: math.dueInPaid.toStringAsFixed(2),
                      errorText: math.enough ? null : s.text('amount_insufficient'),
                    ),
                    onChanged: (_) => setDialog(() {}),
                  ),
                  if (math.changeInPaid > 0.004)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '${s.text('change_due')}: ${money(math.changeInPaid, paidCurrency)}',
                        style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700),
                      ),
                    ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: method,
                    decoration: InputDecoration(labelText: s.text('payment_method')),
                    items: ['cash', 'moncash', 'natcash', 'bank', 'other']
                        .map((m) => DropdownMenuItem(value: m, child: Text(s.text('method_$m'))))
                        .toList(),
                    onChanged: (v) => method = v ?? 'cash',
                  ),
                  if (balance > 0)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(s.text('use_balance')),
                      subtitle: Text('${s.text('balance_available')}: ${money(balance, currency)}'),
                      value: creditUsed > 0,
                      onChanged: (v) => setDialog(
                        () => creditUsed = v == true ? (balance < applied ? balance : applied) : 0,
                      ),
                    ),
                  if (math.changeInPaid > 0.004)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(s.text('keep_change_as_credit')),
                      subtitle: Text('+${money(math.receivedInBase - math.cashDue, currency)}'),
                      value: keepCredit,
                      onChanged: (v) => setDialog(() => keepCredit = v == true),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(s.text('receipt_auto_email_hint'), style: Theme.of(context).textTheme.bodySmall),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(s.text('cancel'))),
            FilledButton(
              onPressed: applied <= 0 || !math.enough
                  ? null
                  : () => Navigator.pop(
                      context,
                      CollectResult(
                        amount: applied,
                        received: math.receivedInBase,
                        method: method,
                        creditUsed: creditUsed,
                        keepChangeAsCredit: keepCredit,
                        paidCurrency: paidCurrency,
                        exchangeRate: rate > 0 ? rate : null,
                        tendered: math.given,
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
