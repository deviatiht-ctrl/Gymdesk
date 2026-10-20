import '../../../core/sync/sync_models.dart';

const supportedCurrencies = ['USD', 'HTG'];

/// Taux du jour réglé par le propriétaire : HTG pour 1 USD (0 = pas de conversion).
double gymExchangeRate(Json settings) {
  final value = settings['exchange_rate_htg'];
  return value is num && value > 0 ? value.toDouble() : 0;
}

/// Convertit [value] de [from] vers [to] avec [rate] HTG/USD.
double convertCurrency(double value, String from, String to, double rate) {
  if (from == to || rate <= 0) return value;
  return from == 'USD' ? value * rate : value / rate;
}

double round2(double value) => (value * 100).roundToDouble() / 100;

String money(double value, String currency) =>
    '${value.toStringAsFixed(currency == 'HTG' ? 0 : 2)} $currency';

/// Totaux réellement encaissés par devise (billets gardés, monnaie déduite).
Map<String, double> collectedByCurrency(Iterable<Json> payments) {
  final totals = <String, double>{};
  for (final row in payments) {
    final base = row['currency'] as String? ?? 'HTG';
    final paid = row['paid_currency'] as String? ?? base;
    final amount = (row['paid_amount'] as num?)?.toDouble() ??
        ((row['amount'] as num?)?.toDouble() ?? 0) -
            ((row['credit_used'] as num?)?.toDouble() ?? 0) +
            ((row['credit_amount'] as num?)?.toDouble() ?? 0);
    totals[paid] = (totals[paid] ?? 0) + amount;
  }
  return totals;
}
