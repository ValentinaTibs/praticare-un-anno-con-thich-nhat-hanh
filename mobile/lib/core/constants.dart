class AppConstants {
  static const String appName = 'La via della trasformazione';

  // Change to your local IP when testing on a physical device
  static const String baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://10.0.2.2:3000', // Android emulator → localhost
  );

  /// The privacy policy page on the project's website, written by the Super Admin.
  /// The default is provisional until the page is published (#6).
  static const String privacyPolicyUrl = String.fromEnvironment(
    'PRIVACY_POLICY_URL',
    defaultValue: 'https://laviadellatrasformazione.it/privacy',
  );
}
