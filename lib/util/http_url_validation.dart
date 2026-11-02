import 'package:flutter/painting.dart';

import 'package:transparent_image/transparent_image.dart';

/// `true` when [s] is a usable absolute `http`/`https` URL with a non-empty host.
///
/// Catches `https://` / `http://` and other strings that [Image.network] /
/// [CachedNetworkImage] reject with *No host specified in URI*.
bool isUsableHttpImageUrl(String? s) {
  final t = s?.trim();
  if (t == null || t.isEmpty) return false;
  final lo = t.toLowerCase();
  if (!lo.startsWith('http://') && !lo.startsWith('https://')) {
    return false;
  }
  final u = Uri.tryParse(t);
  if (u == null) return false;
  if (u.scheme != 'http' && u.scheme != 'https') return false;
  return u.host.isNotEmpty;
}

/// Safe [ImageProvider] for bad URLs so the widget does not throw during build.
ImageProvider get transparentPlaceholderImageProvider => MemoryImage(kTransparentImage);
