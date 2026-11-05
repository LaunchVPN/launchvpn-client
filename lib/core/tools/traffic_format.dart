import 'package:intl/intl.dart';

String formatTraffic(int bytes, {bool connection = false}) {
  // Match the connection page's approved labels; other consumers use IEC units.
  final units = connection
      ? const ['B', 'KB', 'MB', 'GB', 'TB']
      : const ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
  final (value, unit) = _scale(bytes);
  var number = value.toStringAsFixed(
    unit == 0
        ? 0
        : connection
        ? 2
        : 1,
  );
  if (connection && number.contains('.')) {
    number = number.replaceFirst(RegExp(r'\.?0+$'), '');
  }
  return '$number ${units[unit]}';
}

/// The binary units [localizedTraffic] picks from, bytes to terabytes.
enum TrafficUnit { b, kb, mb, gb, tb }

/// [bytes] in the largest binary unit that keeps it at or above one, its
/// number written for [locale]: whole bytes, one decimal place above. The
/// caller words the unit in the language of the screen.
({String number, TrafficUnit unit}) localizedTraffic(int bytes, String locale) {
  final (value, unit) = _scale(bytes);
  return (
    number: NumberFormat(unit == 0 ? '0' : '0.#', locale).format(value),
    unit: TrafficUnit.values[unit],
  );
}

/// [bytes] divided by 1024 until below it, up to terabytes, with the number
/// of divisions.
(double, int) _scale(int bytes) {
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < TrafficUnit.values.length - 1) {
    value /= 1024;
    unit++;
  }
  return (value, unit);
}
