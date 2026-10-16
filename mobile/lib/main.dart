import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    try {
      await Firebase.initializeApp();
    } catch (e) {
      // Until the Firebase project exists (issue #5) the app runs without push notifications.
      debugPrint('Firebase not configured, push notifications disabled: $e');
    }
  }
  runApp(const ProviderScope(child: App()));
}
