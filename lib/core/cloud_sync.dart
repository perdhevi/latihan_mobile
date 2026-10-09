import 'dart:async';

import 'package:flutter/foundation.dart';

import 'credential_store.dart';
import 'fitness_api.dart';
import 'fitness_store.dart';
import 'sync_service.dart';

typedef ApiFactory = FitnessApi Function(
  String url,
  String? refreshToken,
  void Function(String? refreshToken) onRefreshToken,
);

FitnessApi _defaultApi(
  String url,
  String? refreshToken,
  void Function(String?) onRefreshToken,
) =>
    FitnessApi(url, refreshToken: refreshToken, onRefreshToken: onRefreshToken);

/// The cloud session and when to synchronize.
///
/// The session survives restarts: the server URL and refresh token are kept in
/// [credentials]. Syncing runs when the app starts, when it returns to the
/// foreground, and shortly after data is changed. These automatic runs never
/// ask the user anything and never block saving; a problem is recorded in
/// [problem] instead. Local data is never touched by signing out.
class CloudSync extends ChangeNotifier {
  final FitnessStore store;
  final CredentialStore credentials;
  final ApiFactory _apiFactory;

  /// Wait after a change, so a burst of edits is sent once.
  final Duration debounce;

  /// Least time between automatic syncs on returning to the app.
  final Duration minInterval;

  CloudSync(
    this.store, {
    CredentialStore? credentials,
    ApiFactory? apiFactory,
    this.debounce = const Duration(seconds: 5),
    this.minInterval = const Duration(minutes: 1),
  }) : credentials = credentials ?? const SecureCredentialStore(),
       _apiFactory = apiFactory ?? _defaultApi {
    store.onDataChanged = syncSoon;
  }

  FitnessApi? api;
  String? url;
  bool syncing = false;

  /// Signed in, but the account has no cloud profile yet.
  bool needsProfile = false;
  String? displayName;
  String? lastResult;
  DateTime? lastSyncAt;
  String? problem;

  /// The signed-in account differs from the one this device syncs with; only
  /// the user can resolve it (see [sync]).
  bool accountConflict = false;

  Timer? _timer;
  DateTime? _lastAttempt;
  Future<void> _persisting = Future.value();
  bool _disposed = false;

  bool get signedIn => api?.signedIn == true;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    if (store.onDataChanged == syncSoon) store.onDataChanged = null;
    api?.close();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  // -- Session ---------------------------------------------------------------

  void _persist(String? token) {
    final address = url;
    _persisting = _persisting.then(
      (_) => token == null || address == null
          ? credentials.clear()
          : credentials.write(Credentials(address, token)),
    );
  }

  /// Resumes the stored session, if any, and syncs.
  Future<void> restore() async {
    final saved = await credentials.read();
    if (saved == null || _disposed || api != null) return;
    url = saved.url;
    try {
      api = _apiFactory(saved.url, saved.refreshToken, _persist);
    } on ArgumentError {
      await credentials.clear();
      return;
    }
    notifyListeners();
    await sync();
  }

  Future<void> signIn(
    String address,
    String email,
    String password, {
    bool register = false,
  }) async {
    final next = _apiFactory(address.trim(), null, _persist);
    api?.close();
    api = next;
    url = address.trim();
    needsProfile = false;
    displayName = null;
    try {
      await next.signIn(email, password, register: register);
      try {
        displayName = (await next.profile())['display_name'] as String;
      } on ApiException catch (e) {
        if (e.code != 'profile_required') rethrow;
        needsProfile = true;
      }
    } catch (_) {
      if (identical(api, next) && !next.signedIn) api = null;
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  Future<void> createProfile(String name) async {
    displayName = (await api!.createProfile(name))['display_name'] as String;
    needsProfile = false;
    notifyListeners();
  }

  /// Ends the cloud session. Data on this device is kept.
  Future<void> signOut() async {
    final current = api;
    try {
      await current?.signOut();
    } finally {
      _endSession();
      await _persisting;
      await credentials.clear();
    }
  }

  void _endSession() {
    _timer?.cancel();
    api?.close();
    api = null;
    needsProfile = false;
    displayName = null;
    lastResult = null;
    lastSyncAt = null;
    problem = null;
    accountConflict = false;
    notifyListeners();
  }

  // -- Sync ------------------------------------------------------------------

  /// Syncs after changes settle. Called by the store whenever the user saves.
  void syncSoon() {
    if (api == null) return;
    _timer?.cancel();
    _timer = Timer(debounce, sync);
  }

  /// Syncs on returning to the app, at most once per [minInterval].
  void resumed() {
    final last = _lastAttempt;
    if (api == null ||
        (last != null && DateTime.now().difference(last) < minInterval)) {
      return;
    }
    unawaited(sync());
  }

  /// Runs a sync now. [onAccountMismatch] is asked what to do when the account
  /// differs from the one this device last synced with: true erases the device
  /// first, false keeps and uploads its data, null cancels. Without it (the
  /// automatic runs) the mismatch is recorded in [accountConflict].
  Future<SyncReport?> sync({
    Future<bool?> Function()? onAccountMismatch,
  }) async {
    final current = api;
    if (current == null || syncing || needsProfile) return null;
    _timer?.cancel();
    syncing = true;
    problem = null;
    _lastAttempt = DateTime.now();
    notifyListeners();
    try {
      var erased = false;
      SyncReport report;
      try {
        report = await SyncService(store.db, current).sync();
      } on SyncAccountMismatch catch (e) {
        final erase = onAccountMismatch == null
            ? null
            : await onAccountMismatch();
        if (erase == null) {
          accountConflict = true;
          problem = e.message;
          return null;
        }
        await SyncService.unlinkAccount(store.db, eraseData: erase);
        erased = erase;
        report = await SyncService(store.db, current).sync();
      }
      accountConflict = false;
      // Records pulled in (or erased) changed the database under the screens.
      if (report.changedLocal || erased) await store.load();
      lastResult = report.summary;
      lastSyncAt = DateTime.now();
      if (report.failures.isNotEmpty) problem = report.failures.join('\n');
      return report;
    } on SyncException catch (e) {
      problem = e.message;
    } on ApiException catch (e) {
      problem = e.message;
    } catch (_) {
      problem = 'Could not reach the server. Your data is safe on this device.';
    } finally {
      syncing = false;
      // The server rejected the stored session: back to signed out.
      if (identical(api, current) && !current.signedIn) {
        _endSession();
        problem = 'Your cloud session ended. Sign in again to sync.';
        await credentials.clear();
      }
      notifyListeners();
    }
    return null;
  }
}
