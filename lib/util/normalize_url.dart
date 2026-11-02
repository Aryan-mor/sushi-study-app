import 'package:punycoder/punycoder.dart';

/// Whether [url] already carries an http or https scheme.
/// Uses toLowerCase() because users may type mixed-case schemes (e.g. Https://, HTTP://).
bool hasHttpScheme(String url) {
  final lower = url.toLowerCase();
  return lower.startsWith('http://') || lower.startsWith('https://');
}

/// Normalizes a user-entered server URL (trim, default scheme, punycode host).
String normalizeUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return '';

  final withScheme = hasHttpScheme(trimmed) ? trimmed : 'http://$trimmed';
  final parsed = Uri.parse(withScheme);

  final host = parsed.host;
  final hasNonAscii = host.runes.any((c) => c > 0x7F);

  if (!hasNonAscii) return parsed.toString();

  try {
    final encodedHost = const PunycodeCodec().encode(host);
    return parsed.replace(host: encodedHost).toString();
  } catch (_) {
    return parsed.toString();
  }
}
