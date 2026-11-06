import 'package:flutter/material.dart';
import '../auth/auth_errors.dart';
import 'error_retry.dart';

/// Shown at launch when the stored session could not be checked because the
/// server did not answer: the session is kept, and [onLogout] is the way out
/// should the problem never pass.
class SessionUnavailable extends StatelessWidget {
  final VoidCallback onRetry;
  final VoidCallback onLogout;

  const SessionUnavailable({super.key, required this.onRetry, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ErrorRetry(message: serverUnavailableMessage, onRetry: onRetry),
              TextButton(onPressed: onLogout, child: const Text('Esci')),
            ],
          ),
        ),
      ),
    );
  }
}
