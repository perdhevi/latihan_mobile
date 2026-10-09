import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// What is needed to resume a cloud session without a password. The access
/// token is deliberately not kept: it is cheap to get again from this.
class Credentials {
  final String url;
  final String refreshToken;
  const Credentials(this.url, this.refreshToken);
}

abstract class CredentialStore {
  Future<Credentials?> read();
  Future<void> write(Credentials credentials);
  Future<void> clear();
}

/// The platform keystore (Android Keystore, iOS Keychain). If it cannot be
/// reached the app simply behaves as signed out: nothing here may throw.
class SecureCredentialStore implements CredentialStore {
  static const _url = 'cloud_api_url';
  static const _token = 'cloud_refresh_token';
  final FlutterSecureStorage _storage;
  const SecureCredentialStore([this._storage = const FlutterSecureStorage()]);

  @override
  Future<Credentials?> read() async {
    try {
      final url = await _storage.read(key: _url);
      final token = await _storage.read(key: _token);
      return url == null || token == null ? null : Credentials(url, token);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(Credentials credentials) async {
    try {
      await _storage.write(key: _url, value: credentials.url);
      await _storage.write(key: _token, value: credentials.refreshToken);
    } catch (_) {}
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: _url);
      await _storage.delete(key: _token);
    } catch (_) {}
  }
}

/// For tests.
class MemoryCredentialStore implements CredentialStore {
  Credentials? value;
  MemoryCredentialStore([this.value]);
  @override
  Future<Credentials?> read() async => value;
  @override
  Future<void> write(Credentials credentials) async => value = credentials;
  @override
  Future<void> clear() async => value = null;
}
