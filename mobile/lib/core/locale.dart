import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

/// App and admin panel are Italian-only: DateFormat and the Material widgets
/// (date and time pickers included) all use this locale. Call before runApp.
Future<void> initItalianLocale() async {
  Intl.defaultLocale = 'it_IT';
  await initializeDateFormatting('it_IT');
}
