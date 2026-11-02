import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:fladder/sushi/sushi_brand.dart';
import 'package:fladder/sushi/sushi_config.dart';

/// Login header: brand icon + name. Uses the full-color SVG (no theme ShaderMask).
class SushiLoginLogo extends StatelessWidget {
  const SushiLoginLogo({super.key});

  static const double _iconSize = 72;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Image.asset(
                  'icons/sushi_logo_round.png',
                  width: _iconSize,
                  height: _iconSize,
                ),
          const SizedBox(width: 16),
          Text(
            SushiBrand.appName,
            style: theme.textTheme.headlineLarge,
          ),
        ],
      ),
    );
  }
}
