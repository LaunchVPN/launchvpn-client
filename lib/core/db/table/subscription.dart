import 'package:drift/drift.dart';

class Subscription extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text()();

  TextColumn get url => text()();
  TextColumn get userAgent => text().nullable()();

  TextColumn get panel => text().withDefault(const Constant('generic'))();
  TextColumn get mode => text().withDefault(const Constant('appManaged'))();

  TextColumn get ageSecretKey => text().nullable()();

  TextColumn get agePublicKey => text().nullable()();
  BoolColumn get hwidEnabled => boolean().withDefault(const Constant(false))();
  TextColumn get hwid => text().nullable()();

  DateTimeColumn get timestamp => dateTime()();

  IntColumn get uploadBytes => integer().nullable()();
  IntColumn get downloadBytes => integer().nullable()();
  IntColumn get totalBytes => integer().nullable()();
  IntColumn get expireTimestamp => integer().nullable()();
  DateTimeColumn get userInfoUpdatedAt => dateTime().nullable()();

  TextColumn get profileTitle => text().nullable()();
  TextColumn get supportUrl => text().nullable()();
  IntColumn get updateIntervalHours => integer().nullable()();

  TextColumn get announce => text().nullable()();

  /// The text the user closed. Any other announcement still shows.
  TextColumn get dismissedAnnounce => text().nullable()();
}
