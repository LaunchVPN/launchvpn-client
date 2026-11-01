import 'package:collection/collection.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/service/servers/catalog.dart';

/// One entry of the locations screen: a group as the panel names it, or a
/// single server of an ordinary subscription.
class Location {
  Location._({
    required this.id,
    required this.name,
    required this.countryCode,
    required this.automatic,
    required this.delay,
  });

  /// [label] is the panel's name, such as "🇷🇺 AUTO | Обход глушилок".
  factory Location.parse({
    required int id,
    required String label,
    required int delay,
  }) {
    var text = label.trim();
    final flag = _flag.firstMatch(text);
    if (flag != null) text = text.substring(flag.end);
    final automatic = _automaticPrefix.firstMatch(text);
    if (automatic != null) text = text.substring(automatic.end);
    return Location._(
      id: id,
      name: text.replaceAll(_separator, ' · '),
      countryCode: flag == null ? null : _countryCode(flag[1]!),
      automatic: automatic != null,
      delay: delay,
    );
  }

  static final _flag = RegExp(r'^([\u{1F1E6}-\u{1F1FF}]{2})\s*', unicode: true);
  static final _automaticPrefix = RegExp(r'^AUTO\s*\|\s*');
  static final _separator = RegExp(r'\s*\|\s*');
  static const _regionalIndicatorA = 0x1F1E6;

  static String _countryCode(String flag) => String.fromCharCodes(
    flag.runes.map((rune) => rune - _regionalIndicatorA + 0x41),
  );

  final int id;
  final String name;

  /// ISO letters from the panel's flag emoji, which look different on Android.
  final String? countryCode;
  final bool automatic;

  /// A `PingDelayConstants` value until a measurement succeeds.
  final int delay;

  /// The panel's groups for getting around blocking.
  bool get bypass => automatic && name.contains('Обход');
}

/// The panel's groups in its own order, with the automatic ones separated.
class LocationList {
  LocationList.from(ServerCatalog catalog)
    : all = List.unmodifiable([
        for (final row in currentRows(_inPanelOrder(catalog.servers)))
          if (catalog.display(row).readable)
            Location.parse(
              id: row.id,
              label: catalog.display(row).name,
              delay: row.delay,
            ),
      ]);

  final List<Location> all;

  Iterable<Location> get automatic => all.where((item) => item.automatic);
  Iterable<Location> get others => all.where((item) => !item.automatic);
  Location? get first => all.firstOrNull;

  Location? withId(int id) => all.firstWhereOrNull((item) => item.id == id);

  /// The entry for a panel label, whichever of its rows is the current one.
  Location? named(String label) {
    final name = Location.parse(id: 0, label: label, delay: 0).name;
    return all.firstWhereOrNull((item) => item.name == name);
  }

  static List<CoreConfigData> _inPanelOrder(List<CoreConfigData> rows) =>
      rows.sortedBy<num>((row) => row.id);

  /// A refresh keeps the row a starting connection reads next to its new copy,
  /// so the newest row of a provider group is the current one. Expects rows in
  /// ascending ID order.
  static List<CoreConfigData> currentRows(Iterable<CoreConfigData> rows) {
    final current = <Object, CoreConfigData>{};
    for (final row in rows) {
      final key = row.type == CoreConfigType.Remnawave.name ? row.name : row.id;
      current.remove(key);
      current[key] = row;
    }
    return current.values.toList();
  }
}
