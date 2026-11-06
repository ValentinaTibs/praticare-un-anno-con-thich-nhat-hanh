import 'package:intl/intl.dart';

/// A day as the panel shows it, e.g. "12 gennaio 2027", in the viewer's time zone.
String formatDate(DateTime date) => DateFormat('d MMMM y').format(date.toLocal());

/// A moment as the panel shows it, e.g. "12 gennaio 2027, 18:30", in the viewer's time zone.
String formatDateTime(DateTime date) => DateFormat('d MMMM y, HH:mm').format(date.toLocal());
