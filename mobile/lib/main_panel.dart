// Entry point of the web admin panel:
//   flutter run -d chrome -t lib/main_panel.dart --dart-define-from-file=config/panel-prova.json
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/locale.dart';
import 'panel/panel_app.dart';
import 'panel/panel_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initItalianLocale();
  final options = PanelConfig.firebaseOptions;
  if (options == null) {
    debugPrint('Firebase configuration missing: email and password login disabled.');
  } else {
    await Firebase.initializeApp(options: options);
    // Password-reset emails sent by Firebase in Italian.
    await FirebaseAuth.instance.setLanguageCode('it');
  }
  runApp(const ProviderScope(child: PanelApp()));
}
