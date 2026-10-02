import 'package:flutter/material.dart';
import '../services/web_store_service.dart';
import '../utils/app_theme.dart';
import '../utils/formatters.dart';

/// Courier charges for the web store by pincode zone + parcel weight.
/// Stored in webstore/settings under store.shipping and used by the
/// website at checkout, the moment the customer types their pincode.
class ShippingScreen extends StatefulWidget {
  final Map<String, dynamic> shipping;
  const ShippingScreen({super.key, required this.shipping});

  @override
  State<ShippingScreen> createState() => _ShippingScreenState();
}

const _zones = [
  ('local', 'Local', 'Your own pincodes (listed below)'),
  ('state', 'Rest of Tamil Nadu', 'Pincodes starting 60–64'),
  ('india', 'Rest of India', 'All other pincodes'),
];

class _ShippingScreenState extends State<ShippingScreen> {
  late bool _enabled = widget.shipping['enabled'] == true;
  late final _pins = TextEditingController(
      text: ((widget.shipping['localPins'] as List?) ?? const []).join(', '));
  late final Map<String, Map<String, TextEditingController>> _c = {
    for (final z in _zones)
      z.$1: {
        for (final f in ['base', 'baseKg', 'perKg', 'freeAbove'])
          f: TextEditingController(text: _initial(z.$1, f)),
      }
  };

  String _initial(String zone, String field) {
    final r = ((widget.shipping['rates'] as Map?) ?? const {})[zone] as Map?;
    final v = r?[field] as num?;
    if (v == null) return field == 'baseKg' ? '1' : '';
    return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  }

  double _n(String zone, String field) => double.tryParse(_c[zone]![field]!.text.trim()) ?? 0;

  /// Same formula as the website: base covers the first [baseKg] kg; every
  /// started kg after that adds [perKg].
  int _example(String zone, double kg) {
    final baseKg = _n(zone, 'baseKg') > 0 ? _n(zone, 'baseKg') : 1;
    final extra = (kg - baseKg - 1e-9).ceil().clamp(0, 1000);
    return (_n(zone, 'base') + extra * _n(zone, 'perKg')).round();
  }

  Map<String, dynamic> _result() => {
        'enabled': _enabled,
        'localPins': _pins.text
            .split(RegExp(r'[,\s]+'))
            .map((x) => x.trim())
            .where((x) => RegExp(r'^[1-9][0-9]{0,5}\*?$').hasMatch(x))
            .toList(),
        'rates': {
          for (final z in _zones)
            z.$1: {
              'base': _n(z.$1, 'base'),
              'baseKg': _n(z.$1, 'baseKg') > 0 ? _n(z.$1, 'baseKg') : 1,
              'perKg': _n(z.$1, 'perKg'),
              'freeAbove': _n(z.$1, 'freeAbove'),
            }
        },
      };

  Widget _num(TextEditingController c, String label, {String? suffix}) => Expanded(
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: label, suffixText: suffix, isDense: true, border: const OutlineInputBorder()),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffold,
      appBar: AppBar(title: const Text('Delivery charges')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 100),
        children: [
          AppCard(
            padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _enabled,
              title: const Text('Charge by pincode and weight', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Off = the simple flat charge from Shop details'),
              onChanged: (v) => setState(() => _enabled = v),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pins,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Local pincodes',
              hintText: '642001, 642002, 6420*',
              helperText: 'Separate with commas. A * covers a whole area, e.g. 6420*',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          for (final z in _zones) ...[
            AppCard(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(z.$2, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                Text(z.$3, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 10),
                Row(children: [
                  _num(_c[z.$1]!['base']!, 'Base charge', suffix: '₹'),
                  const SizedBox(width: 8),
                  _num(_c[z.$1]!['baseKg']!, 'Covers first', suffix: 'kg'),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  _num(_c[z.$1]!['perKg']!, 'Each extra kg', suffix: '₹'),
                  const SizedBox(width: 8),
                  _num(_c[z.$1]!['freeAbove']!, 'Free above (0 = never)', suffix: '₹'),
                ]),
                const SizedBox(height: 8),
                Text(
                  'Example: 1 kg ${formatCurrency(_example(z.$1, 1))} · 3 kg ${formatCurrency(_example(z.$1, 3))} · '
                  '5 kg ${formatCurrency(_example(z.$1, 5))}',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.profit),
                ),
              ]),
            ),
            const SizedBox(height: 10),
          ],
          Text(
            'Weight is worked out from the cart: kg sizes, pack labels like "25 kg bag", and combos. '
            'Products whose size has no weight count as 1 kg. You can still change the charge on any order.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.4),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () => Navigator.pop(context, _result()),
            child: const Text('Save delivery charges'),
          ),
        ),
      ),
    );
  }
}
