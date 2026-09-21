import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'formatters.dart';

/// One consistent, readable tap-popup for every chart in the app.
///
/// fl_chart's default popup draws the amount in the SAME colour as the
/// bar/line on a dark grey box, with raw unformatted numbers — hard to
/// read. This uses white bold text on a dark background, formats the
/// amount as currency, shows the date/label underneath, and keeps the
/// popup inside the chart so it's never cut off at the edges.
class ChartStyle {
  static const _bg = Color(0xFF263238);
  static const _amount = TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13);
  static const _label = TextStyle(color: Color(0xFFCFD8DC), fontWeight: FontWeight.normal, fontSize: 11);

  static String _pretty(String raw) => raw.length >= 10 ? formatDay(raw) : raw;

  static String _labelAt(List<String> labels, int i) =>
      (i >= 0 && i < labels.length) ? _pretty(labels[i]) : '';

  static BarTouchData barTouch(List<String> labels) => BarTouchData(
        enabled: true,
        touchTooltipData: BarTouchTooltipData(
          getTooltipColor: (_) => _bg,
          tooltipRoundedRadius: 8,
          tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          fitInsideHorizontally: true,
          fitInsideVertically: true,
          getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
            formatCurrency(rod.toY),
            _amount,
            children: [TextSpan(text: '\n${_labelAt(labels, group.x)}', style: _label)],
          ),
        ),
      );

  static LineTouchData lineTouch(List<String> labels) => LineTouchData(
        enabled: true,
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => _bg,
          tooltipRoundedRadius: 8,
          tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          fitInsideHorizontally: true,
          fitInsideVertically: true,
          getTooltipItems: (spots) => spots
              .map((s) => LineTooltipItem(
                    formatCurrency(s.y),
                    _amount,
                    children: [TextSpan(text: '\n${_labelAt(labels, s.x.toInt())}', style: _label)],
                  ))
              .toList(),
        ),
      );
}
