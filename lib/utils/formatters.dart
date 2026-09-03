import 'package:intl/intl.dart';

final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
final dateFormat = DateFormat('dd MMM yyyy, hh:mm a');
final dayFormat = DateFormat('dd MMM yyyy');

String formatCurrency(num value) => currencyFormat.format(value);

String formatDate(String isoString) {
  try {
    return dateFormat.format(DateTime.parse(isoString));
  } catch (_) {
    return isoString;
  }
}

String formatDay(String isoString) {
  try {
    return dayFormat.format(DateTime.parse(isoString));
  } catch (_) {
    return isoString;
  }
}
