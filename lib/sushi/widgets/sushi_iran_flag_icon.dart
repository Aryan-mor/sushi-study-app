import 'package:flutter/material.dart';

/// Lion-and-sun mark for Iranian titles ([iran_splash_256.png]). Not the current flag.
class SushiIranFlagIcon extends StatelessWidget {
  final double size;

  const SushiIranFlagIcon({this.size = 22, super.key});

  static const assetPath = 'assets/sushi/flags/iran_splash_256.png';

  @override
  Widget build(BuildContext context) {
    final cachePx = (size * MediaQuery.devicePixelRatioOf(context)).ceil().clamp(1, 96);
    return Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      cacheWidth: cachePx,
      cacheHeight: cachePx,
      // A decorative flag must never take down a Row's layout: if the asset is
      // missing (e.g. dropped from pubspec), collapse to empty space instead of
      // Flutter's oversized error box.
      errorBuilder: (_, __, ___) => SizedBox(width: size, height: size),
    );
  }
}
