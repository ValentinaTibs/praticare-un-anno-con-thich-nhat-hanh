import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Adds the bundled fonts' SIL Open Font License to the app's license page.
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final family in const ['Inter', 'Literata']) {
      final text = await rootBundle.loadString('assets/fonts/$family-OFL.txt');
      yield LicenseEntryWithLineBreaks([family], text);
    }
  });
}
