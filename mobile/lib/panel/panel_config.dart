import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Build-time configuration of the admin panel, passed with
/// `--dart-define-from-file=config/panel-<env>.json`. The file holds the
/// Firebase web keys, so it is gitignored and never committed.
class PanelConfig {
  static const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const _appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const _messagingSenderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const _authDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
  static const _storageBucket = String.fromEnvironment('FIREBASE_STORAGE_BUCKET');

  /// Firebase web options, or null when the build has no Firebase configuration.
  static FirebaseOptions? get firebaseOptions {
    if (_apiKey.isEmpty || _appId.isEmpty || _projectId.isEmpty) return null;
    return const FirebaseOptions(
      apiKey: _apiKey,
      appId: _appId,
      messagingSenderId: _messagingSenderId,
      projectId: _projectId,
      authDomain: _authDomain,
      storageBucket: _storageBucket,
    );
  }

  /// Development-only login through the backend's /api/auth/dev-login, which
  /// the backend enables only with NODE_ENV=development. Shown in debug builds
  /// started with `--dart-define=DEV_LOGIN=true`.
  static const devLogin = kDebugMode && bool.fromEnvironment('DEV_LOGIN');
}
