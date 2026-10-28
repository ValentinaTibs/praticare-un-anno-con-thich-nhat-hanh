import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initItalianLocale();
  if (!kIsWeb) {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      // Verification and password-reset emails sent by Firebase in Italian.
      await FirebaseAuth.instance.setLanguageCode('it');
    } catch (e) {
      // If Firebase cannot start the app still runs, without push
      // notifications and without login (Firebase email+password).
      debugPrint('Firebase not configured, login and push notifications disabled: $e');
    }
  }
  runApp(const ProviderScope(child: App()));
}
