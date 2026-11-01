import 'dart:convert';

import 'package:dio/dio.dart';

/// What the panel reports about a subscription in its response headers.
/// A malformed or repeated header is unknown, without affecting the others.
class SubscriptionPanelInfo {
  const SubscriptionPanelInfo({
    this.title,
    this.announce,
    this.supportUrl,
    this.updateIntervalHours,
  });

  factory SubscriptionPanelInfo.fromHeaders(Headers headers) {
    String? single(String name) {
      final values = headers[name];
      return values?.length == 1 ? values!.single.trim() : null;
    }

    return SubscriptionPanelInfo(
      title: _parseText(single('profile-title')),
      announce: _parseText(single('announce')),
      supportUrl: _parseSupportUrl(single('support-url')),
      updateIntervalHours: _parseIntervalHours(
        single('profile-update-interval'),
      ),
    );
  }

  final String? title;

  /// A notice for the user, such as planned maintenance.
  final String? announce;
  final String? supportUrl;

  /// How often the panel asks clients to refresh.
  final int? updateIntervalHours;

  static const _base64Prefix = 'base64:';

  static String? _parseText(String? value) {
    if (value == null) return null;
    if (!value.startsWith(_base64Prefix)) return value.isEmpty ? null : value;
    try {
      final decoded = utf8
          .decode(base64.decode(value.substring(_base64Prefix.length)))
          .trim();
      return decoded.isEmpty ? null : decoded;
    } on FormatException {
      return null;
    }
  }

  static String? _parseSupportUrl(String? value) {
    if (value == null) return null;
    final url = Uri.tryParse(value);
    return url != null && url.isScheme('https') && url.host.isNotEmpty
        ? value
        : null;
  }

  static int? _parseIntervalHours(String? value) {
    if (value == null || !RegExp(r'^[0-9]+$').hasMatch(value)) return null;
    final hours = int.tryParse(value);
    return hours != null && hours > 0 ? hours : null;
  }
}
