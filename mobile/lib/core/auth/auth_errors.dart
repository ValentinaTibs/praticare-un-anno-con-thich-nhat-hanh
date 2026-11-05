import 'package:firebase_auth/firebase_auth.dart' as fb;
import '../api/api_client.dart';

/// Raised for auth problems that are not a [fb.FirebaseAuthException] nor an
/// [ApiException] (Firebase not configured, no signed-in Firebase user).
class AuthFlowException implements Exception {
  final String message;
  AuthFlowException(this.message);

  @override
  String toString() => message;
}

/// Short Italian message for any error coming out of the auth flow.
String authErrorMessage(Object error) {
  if (error is fb.FirebaseAuthException) {
    return switch (error.code) {
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' ||
      'INVALID_LOGIN_CREDENTIALS' =>
        'Email o password non corretti.',
      'email-already-in-use' => 'Esiste già un account con questa email.',
      'weak-password' => 'Password troppo debole: usa almeno 6 caratteri.',
      'invalid-email' => 'Indirizzo email non valido.',
      'too-many-requests' => 'Troppi tentativi. Riprova tra qualche minuto.',
      'user-disabled' => 'Questo account è stato disabilitato.',
      'network-request-failed' => 'Errore di rete. Controlla la connessione.',
      _ => 'Errore di autenticazione (${error.code}).',
    };
  }
  if (error is ApiException) {
    return error.contact != null ? '${error.message}\nContatto: ${error.contact}' : error.message;
  }
  if (error is AuthFlowException) return error.message;
  return 'Si è verificato un errore. Riprova.';
}
