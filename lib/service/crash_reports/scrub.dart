import 'package:sentry_flutter/sentry_flutter.dart';

/// Takes out of a crash report what could identify the person or their
/// servers: links (subscription, share and server ones), email addresses,
/// UUIDs and the HWID, IP addresses and host names, which also covers DNS
/// queries. Stack frames, types and the device model stay, since they locate
/// the bug and name nobody. Pure but for one thing: as Sentry's `beforeSend`
/// expects, it edits [event] in place and returns it.
SentryEvent scrubEvent(SentryEvent event) {
  event
    ..serverName = null
    ..request = null
    ..transaction = _scrubNullable(event.transaction)
    ..message = switch (event.message) {
      final message? => SentryMessage(
        scrubText(message.formatted),
        template: _scrubNullable(message.template),
        params: message.params?.map(_scrubValue).toList(),
      ),
      null => null,
    }
    ..tags = event.tags?.map((key, value) => MapEntry(key, scrubText(value)))
    ..breadcrumbs = event.breadcrumbs?.map(scrubBreadcrumb).toList()
    // Only the SDK's random installation id, which counts affected devices.
    ..user = switch (event.user?.id) {
      final id? => SentryUser(id: id),
      null => null,
    };
  event.contexts.device?.name = null;
  // ignore: deprecated_member_use
  event.extra = _scrubMap(event.extra);
  // Flutter's error details, such as the text of an overflowing widget. The
  // typed contexts (device, system, App) hold no strings of ours.
  for (final key in event.contexts.keys.toList()) {
    final value = event.contexts[key];
    if (value is String || value is Map || value is Iterable) {
      event.contexts[key] = _scrubValue(value);
    }
  }
  for (final exception in event.exceptions ?? const <SentryException>[]) {
    exception.value = _scrubNullable(exception.value);
  }
  return event;
}

Breadcrumb scrubBreadcrumb(Breadcrumb breadcrumb) => breadcrumb
  ..message = _scrubNullable(breadcrumb.message)
  ..data = _scrubMap(breadcrumb.data);

/// [text] with every link, email, UUID, IP address and host name replaced by
/// a placeholder that names its kind.
String scrubText(String text) => _patterns.fold(
  text,
  (text, pattern) => text.replaceAllMapped(pattern.match, pattern.replace),
);

typedef _Pattern = ({RegExp match, String Function(Match) replace});

// Order matters: a link holds hosts, emails and UUIDs, an email holds a host.
final List<_Pattern> _patterns = [
  _fixed(RegExp(r'[a-z][a-z0-9+.-]*://\S+', caseSensitive: false), '<link>'),
  _fixed(RegExp(r'[\w.+-]+@[\w-]+(?:\.[\w-]+)+'), '<email>'),
  _fixed(
    RegExp(
      r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
      caseSensitive: false,
    ),
    '<id>',
  ),
  // Android's HWID, the ANDROID_ID: 16 hex digits, no dashes.
  _fixed(RegExp(r'\b[0-9a-f]{16}\b', caseSensitive: false), '<id>'),
  _fixed(RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b'), '<ip>'),
  // Three colons at least, or a `::` anywhere (`2001:db8::`, `::1`), so times
  // such as 12:30:45 stay.
  _fixed(
    RegExp(
      r'(?<![0-9a-z:])(?:'
      r'(?:[0-9a-f]{1,4}:){3,7}[0-9a-f]{1,4}'
      r'|(?:[0-9a-f]{1,4}:)+:(?:[0-9a-f]{1,4}(?::[0-9a-f]{1,4})*)?'
      r'|::[0-9a-f]{1,4}(?::[0-9a-f]{1,4})*'
      r')(?![0-9a-z:])',
      caseSensitive: false,
    ),
    '<ip>',
  ),
  // Letters of any script, for names such as `vpn.сервер.рф`.
  (
    match: RegExp(
      r'(?<![\p{L}\p{N}-])'
      r'(?:[\p{L}\p{N}](?:[\p{L}\p{N}-]*[\p{L}\p{N}])?\.)+(\p{L}{2,24})'
      r'(?![\p{L}\p{N}-])',
      unicode: true,
    ),
    // File names and Dart names such as `AppLifecycleState.resumed` look like
    // hosts and help find the bug. A host is one case per label.
    replace: (match) =>
        _fileExtensions.contains(match[1]!.toLowerCase()) ||
            match[0]!.split('.').any(_mixedCase.hasMatch)
        ? match[0]!
        : '<host>',
  ),
];

_Pattern _fixed(RegExp match, String placeholder) =>
    (match: match, replace: (_) => placeholder);

final _mixedCase = RegExp(r'^(?=.*\p{Lu})(?=.*\p{Ll})', unicode: true);

// No `so`: it is also Somalia's domain.
const _fileExtensions = {
  'dart', 'db', 'json', 'yaml', 'txt', 'log', 'dat', 'kt', 'java', 'swift', //
  'plist', 'xml', 'png', 'jpg', 'html', 'js', 'sqlite', 'ttf',
};

String? _scrubNullable(String? text) => text == null ? null : scrubText(text);

Map<String, dynamic>? _scrubMap(Map<String, dynamic>? map) =>
    map?.map((key, value) => MapEntry(key, _scrubValue(value)));

Object? _scrubValue(Object? value) => switch (value) {
  final String text => scrubText(text),
  final Map<String, dynamic> map => _scrubMap(map),
  final Map<Object?, Object?> map => {
    for (final MapEntry(:key, :value) in map.entries) key: _scrubValue(value),
  },
  final Iterable<Object?> list => list.map(_scrubValue).toList(),
  _ => value,
};
