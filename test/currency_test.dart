import 'package:flutter_test/flutter_test.dart';
import 'package:gym_desk/features/payments/domain/currency.dart';
import 'package:gym_desk/features/payments/domain/payment.dart';
import 'package:gym_desk/features/payments/presentation/collect_payment_dialog.dart';

void main() {
  test('USD plan paid in HTG: due, change and base amount', () {
    const math = CashierMath(currency: 'USD', paidCurrency: 'HTG', rate: 132, cashDue: 25, tendered: 3500);
    expect(math.dueInPaid, 3300);
    expect(math.enough, isTrue);
    expect(math.changeInPaid, 200);
    expect(math.receivedInBase, closeTo(25 + 200 / 132, 0.01));
  });

  test('insufficient HTG is rejected and rounding never undercuts the due', () {
    const short = CashierMath(currency: 'USD', paidCurrency: 'HTG', rate: 132, cashDue: 25, tendered: 3000);
    expect(short.enough, isFalse);
    const exact = CashierMath(currency: 'USD', paidCurrency: 'HTG', rate: 131.37, cashDue: 17.5);
    expect(exact.receivedInBase, 17.5);
  });

  test('payment row keeps plan currency and records the HTG actually kept', () {
    const command = PaymentCommand(
      memberId: 'm',
      amount: 25,
      currency: 'USD',
      method: 'cash',
      receivedAmount: 25,
      paidCurrency: 'HTG',
      exchangeRate: 132,
      tenderedAmount: 3500,
    );
    expect(command.paidAmount, 3300);
    final totals = collectedByCurrency([
      {'amount': 25, 'currency': 'USD', 'paid_currency': 'HTG', 'paid_amount': 3300},
      {'amount': 30, 'currency': 'USD'},
      {'amount': 30, 'currency': 'USD', 'credit_used': 10},
    ]);
    expect(totals, {'HTG': 3300.0, 'USD': 50.0});
  });

  test('conversion is identity without a rate', () {
    expect(convertCurrency(10, 'USD', 'HTG', 0), 10);
    expect(convertCurrency(264, 'HTG', 'USD', 132), 2);
    expect(gymExchangeRate({'exchange_rate_htg': 132}), 132);
    expect(gymExchangeRate({}), 0);
  });
}
