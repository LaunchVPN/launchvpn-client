import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The device session's token pair. Access lives an hour, refresh 90 days and
/// rotates on every use.
final class AccountTokens {
  const AccountTokens({required this.access, required this.refresh});

  final String access;
  final String refresh;
}

/// Keeps the session in the platform's secure store: the Keychain on iOS, a
/// Keystore-encrypted file on Android. Nothing here goes to SharedPreferences.
final class AccountSessionStore {
  AccountSessionStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // Readable while locked after the first unlock, never restored to
            // another device from a backup.
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  static const _access = 'account.access';
  static const _refresh = 'account.refresh';
  static const _subscription = 'account.subscription';

  final FlutterSecureStorage _storage;

  Future<AccountTokens?> readTokens() async {
    final access = await _storage.read(key: _access);
    final refresh = await _storage.read(key: _refresh);
    if (access == null || refresh == null) return null;
    return AccountTokens(access: access, refresh: refresh);
  }

  Future<void> saveTokens(AccountTokens tokens) async {
    await _storage.write(key: _access, value: tokens.access);
    await _storage.write(key: _refresh, value: tokens.refresh);
  }

  Future<void> clearTokens() async {
    await _storage.delete(key: _access);
    await _storage.delete(key: _refresh);
  }

  /// Marks the subscription the account brought, so signing out can remove
  /// it and keep one added from a link.
  Future<void> saveSubscriptionUrl(String url) =>
      _storage.write(key: _subscription, value: url);
}
