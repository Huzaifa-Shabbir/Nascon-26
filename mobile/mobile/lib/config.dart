import 'package:flutter_dotenv/flutter_dotenv.dart';

const _fallbackBackendUrl = 'http://10.0.2.2:8080';

/// Load backend URL from the bundled env asset.
///
/// The release APK ships `.env.example` (see pubspec assets). Keep a local
/// `.env` in sync for editors; copy its values into `.env.example` before a
/// release build if you need a different default URL. Settings can still
/// override at runtime.
Future<void> loadEnv() async {
  await dotenv.load(fileName: '.env.example');
}

/// Default API base URL from env (Settings / local DB can still override).
String defaultBackendUrl() {
  final raw = dotenv.env['BACKEND_URL']?.trim();
  if (raw == null || raw.isEmpty) return _fallbackBackendUrl;
  return raw.replaceAll(RegExp(r'/$'), '');
}
