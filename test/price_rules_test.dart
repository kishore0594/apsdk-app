import 'package:flutter_test/flutter_test.dart';
import 'package:madhura_agro_traders/services/pricing.dart';

// The owner's agreed examples (October 2026). If one of these changes,
// prices or partner commission in the app have changed.
void main() {
  const r = PriceRules();

  test('bills share is 10.5%', () {
    expect(r.billsPct, closeTo(10.5, 0.001));
  });

  test('Kambu IR8 (cost 38): shop 50, online 68', () {
    expect(r.shopPrice(38, 'Millets'), 50);
    expect(r.onlinePlan(38, 'Millets', true).price, 68);
    expect(r.onlineCeiling(38, 'Millets', true), 71);
  });

  test('Kambu IR8 online 68: commission 5.1, profit 8.7', () {
    final b = r.onlineBreak(68, 38, 'Millets', true);
    expect(b.commission, closeTo(5.10, 0.01));
    expect(b.expenses, closeTo(16.18, 0.01));
    expect(b.profit, closeTo(8.72, 0.01));
  });

  test('market inside the band is matched; above the band uses the ceiling', () {
    expect(r.onlinePlan(38, 'Millets', true, market: 69).price, 69);
    expect(r.onlinePlan(38, 'Millets', true, market: 80).price, 71);
  });

  test('lower market: commission and profit cut in the same proportion', () {
    final p = r.onlinePlan(38, 'Millets', true, market: 62);
    expect(p.price, 62);
    expect(p.commissionCut, isTrue);
    expect(p.commissionPct / p.profitPct, closeTo(7.5 / 12, 0.001));
    expect(p.commissionPct, closeTo(5.36, 0.02));
  });

  test('never below half: price stays above a very low market', () {
    final p = r.onlinePlan(38, 'Millets', true, market: 55);
    expect(p.kind, PlanKind.aboveMarket);
    expect(p.price, 59);
    expect(p.commissionPct, closeTo(3.75, 0.001));
  });

  test('partner commission per line', () {
    expect(r.lineCommission('Millets', 2, 136), closeTo(10.2, 0.001));
    expect(r.lineCommission('Rice', 1, 1500), closeTo(30, 0.001));
    expect(r.lineCommission('Cattle Feeds', 3, 4200), 45);
    expect(r.lineCommission('Cattle Feeds', 3, 90, byKg: true), 0);
    expect(r.lineCommission('Millets', 1, 62, productPct: 5.36), closeTo(3.32, 0.01));
  });

  test('partner programme OFF: no commission, lower online price', () {
    final off = PriceRules.fromMap({'partners_on': false});
    expect(off.commissionFor('Millets'), 0);
    expect(off.lineCommission('Millets', 2, 136), 0);
    expect(off.onlinePlan(38, 'Millets', true).price, 61); // (38 + 7) ÷ (1 − 10.5% − 3% − 12%)
    expect(off.onlineBreak(61, 38, 'Millets', true).commission, 0);
  });

  test('cattle feed and rice use the 8% lowest profit', () {
    expect(r.shopProfitFor('Cattle Feeds'), 8);
    expect(r.shopProfitFor('Rice'), 8);
    expect(r.shopProfitFor('Millets'), 12);
  });

  test('price alert only for cost up 3%+ with low profit, or a loss', () {
    final up = {'cost_price': 2245, 'cost_prev': 1900, 'selling_price': 2650, 'category': 'Cattle Feeds', 'unit': 'Nos', 'web_visible': false};
    expect(RuleCheck.of(up, r).alert, isTrue); // cost +18%, profit 4.8% < 8%
    final steady = {'cost_price': 2245, 'selling_price': 2650, 'category': 'Cattle Feeds', 'unit': 'Nos', 'web_visible': false};
    expect(RuleCheck.of(steady, r).alert, isFalse); // below target but cost did not go up: no alert
  });
}
