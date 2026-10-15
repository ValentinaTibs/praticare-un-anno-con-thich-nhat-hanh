class AppConstants {
  // Change to your local IP when testing on a physical device
  static const String baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://10.0.2.2:3000', // Android emulator → localhost
  );

  static const String socketUrl = baseUrl;
}
