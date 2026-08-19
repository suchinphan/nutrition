import 'package:flutter/foundation.dart'
    show
        kIsWeb,
        defaultTargetPlatform,
        TargetPlatform,
        kReleaseMode;

/// Central API base URL configuration for the mobile app.
///
/// Set `productionApiBase` to your real production API URL (must include scheme).
/// In debug mode this will return a local development URL for convenience.
const String productionApiBase = 'https://REPLACE_WITH_PRODUCTION_API';

String getApiBase() {
  if (kReleaseMode) {
    return productionApiBase;
  }

  // Debug / profile: map to emulator/local addresses for convenience.
  if (kIsWeb) return 'http://127.0.0.1:5000';
  if (defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:5000';
  }
  return 'http://127.0.0.1:5000';
}
