import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_core/firebase_core.dart';
import '../../core/auth/auth_errors.dart';

/// The Firebase Authentication steps the panel needs, behind an interface so
/// that tests can replace Firebase.
abstract class PanelFirebase {
  /// Signs in with email and password and returns a fresh ID token, or null
  /// when the email address is not verified yet.
  Future<String?> signIn(String email, String password);

  Future<void> sendPasswordReset(String email);

  Future<void> signOut();
}

class FirebasePanelAuth implements PanelFirebase {
  /// Resolved lazily: the panel starts even without Firebase configuration,
  /// only email and password login is unavailable.
  fb.FirebaseAuth get _auth {
    if (Firebase.apps.isEmpty) {
      throw AuthFlowException('Accesso non disponibile: Firebase non è configurato.');
    }
    return fb.FirebaseAuth.instance;
  }

  @override
  Future<String?> signIn(String email, String password) async {
    final cred = await _auth.signInWithEmailAndPassword(email: email, password: password);
    final user = cred.user;
    if (user == null) throw AuthFlowException('Accesso non riuscito. Riprova.');
    if (!user.emailVerified) return null;
    // Forced refresh, so that the token carries the current email_verified claim.
    final idToken = await user.getIdToken(true);
    if (idToken == null) throw AuthFlowException('Accesso non riuscito. Riprova.');
    return idToken;
  }

  @override
  Future<void> sendPasswordReset(String email) => _auth.sendPasswordResetEmail(email: email);

  @override
  Future<void> signOut() async {
    if (Firebase.apps.isEmpty) return;
    try {
      await fb.FirebaseAuth.instance.signOut();
    } catch (_) {}
  }
}
