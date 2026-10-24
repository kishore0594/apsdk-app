import 'package:flutter/material.dart';
import '../services/finance_service.dart';
import 'finance_screen.dart' show rs, pct, daysTxt;

/// "Why this target?" — plain words behind every KPI and statement line:
/// what it means, why the target, what this period's number says, and
/// one thing to do.
class ExplainData {
  final String what, why, now, action;
  const ExplainData(this.what, this.why, this.now, this.action);
}

ExplainData explainKpi(FinanceService svc, Kpi k, FinFigures f) {
  final s = svc.settings;
  final cur = f.period.isCurrent;
  switch (k) {
    case Kpi.netProfit:
      final v = cur ? f.projectedNetMargin : f.netMargin;
      return ExplainData(
        'What is left from sales after paying for the goods AND every expense — rent, EB, wages/your salary, '
        'transport and the rest — and after the value lost while customers take time to pay credit. '
        'This is the shop\'s real earning.',
        'Official Tamil Nadu inflation is ${pct(s.officialInflation)} (Sep 2026), but real family costs — school fees, '
            'wages, land, health — rise about ${pct(s.realInflation)} a year (your estimate). Profit below that means the '
            'business shrinks in real value. ${pct(s.targetNet)} covers it and leaves room to grow.',
        cur
            ? 'So far ${pct(f.netMargin)} (${rs(f.netProfit)}). At this pace the period ends at ${pct(v)}.'
            : '${pct(f.netMargin)} of sales = ${rs(f.netProfit)}.',
        v >= s.targetNet
            ? 'On target — keep the margin and grow sales.'
            : 'Open the culprit list below: fix prices of the top items first, and push higher-margin items '
                '(millets, own Madhura packs) in offers and status videos.',
      );
    case Kpi.grossMargin:
      return ExplainData(
        'Of every ₹100 sold, how much is left after the purchase cost of those goods (before expenses).',
        'Expenses take about ${pct(s.maxExpense)} of sales and you want ${pct(s.targetNet)} profit, so about '
            '${pct(s.targetGross)} must be left after purchase cost. Price = cost ÷ (1 − margin): for ${pct(s.targetGross)}, '
            'cost ₹100 → sell ₹${(100 / (1 - s.targetGross / 100)).round()}.',
        '${pct(f.grossMargin)} this period (${rs(f.grossProfit)} on ${rs(f.netSales)}).',
        f.grossMargin >= s.targetGross
            ? 'Good. Re-check prices whenever supplier rates rise.'
            : 'See which items are below target below. Price on your NEXT purchase cost, not old stock cost.',
      );
    case Kpi.netSales:
      final prev = svc.figures(f.period.prev).netSales;
      return ExplainData(
        'Sales after bill discounts (delivery charges not included).',
        'Fixed costs (${rs(s.fixedTotal)}/month) stay the same, so more sales means a smaller expense share and more '
            'profit. Sales must grow at least as fast as real inflation (~${pct(s.realInflation)} a year).',
        cur
            ? '${rs(f.netSales)} so far; at this pace ${rs(f.projectedSales)} vs ${rs(prev)} ${f.period.prevWord}.'
            : '${rs(f.netSales)} vs ${rs(prev)} ${f.period.prevWord}.',
        'The list below shows which items sold less than before — bring them back with offers or a status video.',
      );
    case Kpi.expenseRatio:
      final er = cur ? f.itemExpenseRatio : f.expenseRatio;
      return ExplainData(
        'Expenses as a share of sales: ₹ of expenses for every ₹100 sold.',
        'Keep it at or below ${pct(s.maxExpense)} so ${pct(s.targetNet)} profit is possible with a ~${pct(s.targetGross)} margin. '
            'Your fixed costs are about ${rs(s.fixedTotal)} a month — the way to lower this share is MORE SALES, not cutting your salary.',
        '${pct(er)}${cur ? ' (full-period expenses against sales at this pace)' : ''}.',
        'Watch any head that grew compared with last period (orange in the list).',
      );
    case Kpi.breakEven:
      final be = f.breakEven;
      final ts = f.targetSales(s.targetNet);
      return ExplainData(
        'The sales needed just to pay all expenses (expenses ÷ margin). Below it the shop loses money; above it is profit.',
        'Knowing this number tells you the daily sales you must cross. For ${pct(s.targetNet)} profit you need more: '
            'expenses ÷ (margin − ${pct(s.targetNet)}).',
        be == null
            ? 'Margin is zero or negative this period — no break-even possible.'
            : 'Break-even ${rs(be)} (${rs(be / f.period.totalDays)} a day). For ${pct(s.targetNet)} profit: '
                '${ts == null ? 'raise the margin above ${pct(s.targetNet)} first' : '${rs(ts)} (${rs(ts / f.period.totalDays)} a day)'}.',
        'A higher margin lowers both numbers a lot — that is why millets and own packs matter.',
      );
    case Kpi.collection:
      return ExplainData(
        'Money actually received (cash at the counter + old credit collected) for every ₹100 billed.',
        'Credit sales are profit on paper, not money in hand. Below ${pct(s.minCollection)} your cash gets stuck with customers.',
        '${pct(f.collectionRatio)} — billed ${rs(f.revenue)}, received ${rs(f.cashSales + f.creditCollected)}.',
        'Follow up the customers at the top of the list below; send WhatsApp reminders.',
      );
    case Kpi.credit:
      return ExplainData(
        'How many days of sales are sitting with customers as unpaid credit (credit owed ÷ sales per day).',
        'The older a due gets, the harder it is to recover. Over ${s.maxCreditDays.round()} days it ties up your cash; over '
            '${(s.maxCreditDays * 2).round()} days treat it as a risk.',
        '${daysTxt(f.creditDays)} — customers owe ${rs(f.receivables)}.',
        'Collect the oldest dues first (top of the list).',
      );
    case Kpi.stock:
      return ExplainData(
        'How many days your current stock lasts at this period\'s sales rate (stock at cost ÷ cost of goods sold per day).',
        'Grains lose moisture and quality, and stock is cash sitting on the shelf. Over ${s.maxStockDays.round()} days the money '
            'could be working elsewhere.',
        '${daysTxt(f.stockDays)} — stock worth ${rs(f.stockValue)} at cost (from Inventory: quantity × cost price).',
        'Clear the top items below with an offer or a status video, and buy smaller quantities of them next time.',
      );
    case Kpi.supplier:
      return ExplainData(
        'What the shop still has to pay suppliers.',
        'Supplier credit is free money while it lasts, but late payments cost good rates and trust.',
        '${rs(f.payables)} to pay; ${rs(f.supplierPaid)} paid this period.',
        'Pay on the agreed dates; ask for better rates when you pay early.',
      );
    case Kpi.avgBill:
      return ExplainData(
        'Average amount per bill (sales ÷ number of bills).',
        'Selling one more item to a customer who is already buying is the cheapest way to grow — no new customer needed.',
        '${rs(f.avgBill)} over ${f.bills} bills.',
        'Suggest a matching item at billing (e.g. millet flour with grains, a combo pack).',
      );
  }
  // ignore: dead_code
  return const ExplainData('', '', '', '');
}

/// Statement lines (P&L, cash flow, balance sheet).
const lineExplain = {
  'gross_sales': 'Total of all bills before bill discounts (delivery charges not included).',
  'discounts': 'Discounts given on bills. Every ₹ of discount comes straight out of profit.',
  'net_sales': 'Sales after discounts — the base for every "% of sales" figure.',
  'cogs': 'Cost of goods sold: the purchase cost of exactly what was sold (saved with each bill), not what you bought this month.',
  'gross_profit': 'Net sales minus cost of goods sold. Must cover all expenses AND leave your profit target.',
  'expense': 'One expense head. Fixed monthly costs are added automatically on the 1st (change them under ⚙).',
  'expenses': 'All running costs of the shop, including wages/your salary. Your salary is a real cost — counting it shows the true profit.',
  'delivery': 'Delivery charges customers paid on web orders. They help cover the delivery cost.',
  'operating': 'Profit from running the shop: gross profit + delivery charges − expenses.',
  'stock_loss': 'Stock adjustments valued at cost: moisture loss, damage, counting corrections. Keep it under 1% of sales.',
  'net_profit': 'What the shop REALLY earned: after goods, every expense, stock loss, bad debts AND the value lost while customers take time to pay. Target: at least the % you set (12%).',
  'book_profit': 'Profit as an accountant writes it: after expenses, stock loss and bad debts — before counting the credit delay.',
  'bad_debts': 'Credit you wrote off because it will never be paid (Debts tab → Write off). A direct loss.',
  'credit_delay': 'Money paid late is worth less: prices rise while you wait. Cost = credit given × inflation a year × days customers take ÷ 365. Collecting faster or selling for cash removes it.',
  'provision': 'Dues unlikely to come: half of dues 91–180 days old and all over 180 days. Shown so the balance sheet isn\'t too rosy.',
  'delay_days': 'Measured from your own records: how many days, on average, passed between giving credit and being paid (last 12 months). Your figure in ⚙ is used for the credit delay cost.',
  'cash_start': 'Cash in the drawer + bank at the start of the period (worked out from your starting cash).',
  'cash_sales': 'Money received at the counter for cash and part-paid bills.',
  'credit_collected': 'Money customers paid against old credit.',
  'supplier_paid': 'Payments made to suppliers.',
  'cash_end': 'Starting cash + money in − money out. If the starting cash is an estimate, so is this.',
  'credit_given': 'Sold on credit — earned, but not cash yet.',
  'purchases': 'Stock bought from suppliers (paid or not).',
  'stock_value': 'Every item in Inventory: quantity in stock × cost price.',
  'receivables': 'Total credit customers still owe you.',
  'payables': 'Total you still owe suppliers.',
  'loans': 'No loans (as you told us). Add one in ⚙ later if needed.',
  'capital': 'Owner\'s money in the business: what the shop owns minus what it owes. It should grow every year by at least your profit.',
  'working_capital': 'Money free to run the shop day to day (owns − owes). Too low means you can\'t buy stock when needed.',
  'current_ratio': 'Owns ÷ owes. 1.5 or more is healthy; below 1 the shop can\'t pay all dues from its own stock, credit and cash.',
};

void showLineExplain(BuildContext context, String title, String key) {
  final text = lineExplain[key];
  if (text == null) return;
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(text, style: const TextStyle(fontSize: 14, height: 1.4)),
        ]),
      ),
    ),
  );
}

void showExplain(BuildContext context, FinanceService svc, Kpi k, FinFigures f) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(kpiNames[k]!, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          ExplainCard(ex: explainKpi(svc, k, f)),
        ]),
      ),
    ),
  );
}

class ExplainCard extends StatelessWidget {
  final ExplainData ex;
  const ExplainCard({super.key, required this.ex});

  @override
  Widget build(BuildContext context) {
    Widget part(IconData icon, String title, String text, Color color) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: color)),
                const SizedBox(height: 2),
                Text(text, style: const TextStyle(fontSize: 13.5, height: 1.35)),
              ]),
            ),
          ]),
        );
    return Card(
      color: const Color(0xFFF8FAF7),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 2),
        child: Column(children: [
          part(Icons.menu_book_outlined, 'What it means', ex.what, const Color(0xFF1E6F5C)),
          part(Icons.flag_outlined, 'Why this target', ex.why, const Color(0xFF7C3AED)),
          part(Icons.insights_outlined, 'Your number', ex.now, const Color(0xFF2563EB)),
          part(Icons.task_alt, 'What to do', ex.action, const Color(0xFFD97706)),
        ]),
      ),
    );
  }
}
