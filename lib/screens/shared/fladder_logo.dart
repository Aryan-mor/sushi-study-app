import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/sushi/sushi_brand.dart';
import 'package:fladder/screens/shared/fladder_icon.dart';
import 'package:fladder/util/application_info.dart';
import 'package:fladder/util/string_extensions.dart';
import 'package:fladder/util/theme_extensions.dart';

class FladderLogo extends ConsumerWidget {
  const FladderLogo({super.key});

  /// [String.capitalize] lowercases the rest of the string, which breaks "Sushi".
  static String _logoAppName(String applicationName) {
    if (applicationName == SushiBrand.appName) return applicationName;
    return applicationName.capitalize();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Hero(
      tag: "Fladder_Logo_Tag",
      child: Wrap(
        runAlignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.center,
        spacing: 16,
        runSpacing: 8,
        children: [
          const FladderIcon(),
          Text(
            _logoAppName(ref.read(applicationInfoProvider).name),
            style: context.textTheme.displayLarge,
            textAlign: TextAlign.center,
          )
        ],
      ),
    );
  }
}
