import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/sushi/sushi_about_settings_page.dart';

@RoutePage()
class AboutSettingsPage extends ConsumerWidget {
  const AboutSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const SushiAboutSettingsPage();
  }
}
