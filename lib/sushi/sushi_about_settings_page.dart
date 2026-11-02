import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/sushi/sushi_dmca_page.dart';
import 'package:fladder/sushi/sushi_login_kind_store.dart';
import 'package:fladder/sushi/sushi_tdlib_bridge_controller.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/src/tdlib_bridge.g.dart';
import 'package:fladder/screens/settings/settings_scaffold.dart';
import 'package:fladder/screens/shared/fladder_icon.dart';
import 'package:fladder/screens/shared/fladder_logo.dart';
import 'package:fladder/util/application_info.dart';
import 'package:fladder/util/list_padding.dart';
import 'package:fladder/util/localization_helper.dart';

class SushiAboutSettingsPage extends ConsumerStatefulWidget {
  const SushiAboutSettingsPage({super.key});

  @override
  ConsumerState<SushiAboutSettingsPage> createState() => _SushiAboutSettingsPageState();
}

class _SushiAboutSettingsPageState extends ConsumerState<SushiAboutSettingsPage> {
  SushiLoginKind? _loginKind;

  @override
  void initState() {
    super.initState();
    _loadLoginKind();
  }

  Future<void> _loadLoginKind() async {
    final accountId = ref.read(userProvider)?.id;
    final controller = SushiTdlibBridgeController.instance();
    final hasBotToken = await controller.hasCachedBotToken();
    if (!mounted) return;
    final kind = await SushiLoginKindStore.resolve(
      accountId: accountId,
      tdlibUserSessionReady:
          controller.state.kind == SushiTdlibAuthStateKind.ready && !controller.nativeSessionIsBot,
      hasBotToken: hasBotToken,
      nativeWaitingForUserAuth: controller.state.kind == SushiTdlibAuthStateKind.waitingForPhoneNumber ||
          controller.state.kind == SushiTdlibAuthStateKind.failed,
    );
    if (!mounted) return;
    setState(() => _loginKind = kind);
  }

  Future<void> _openSupport(BuildContext context) async {
    final opened = await sushiOpenSupportChannel();
    if (opened || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(SushiDmcaCopy.of(context).openFailed)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final applicationInfo = ref.watch(applicationInfoProvider);

    return SettingsScaffold(
      label: '',
      items: [
        const FladderLogo(),
        Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(context.localized.aboutVersion(applicationInfo.versionAndPlatform)),
            Text(context.localized.aboutBuild(applicationInfo.buildNumber)),
            if (_loginKind != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  switch (_loginKind!) {
                    SushiLoginKind.session => context.localized.sushiAboutLoginSession,
                    SushiLoginKind.bot => context.localized.sushiAboutLoginBot,
                  },
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            const SizedBox(height: 16),
            const Text('A test and study project'),
          ],
        ),
        const FractionallySizedBox(
          widthFactor: 0.25,
          child: Divider(
            indent: 16,
            endIndent: 16,
          ),
        ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.tonal(
              onPressed: () => showLicensePage(
                context: context,
                applicationIcon: const FladderIcon(size: 55),
                applicationVersion: applicationInfo.versionPlatformBuild,
                applicationLegalese: 'Sushi is a modified version of Fladder (DonutWare).\n'
                    'Free software under the GNU GPL v3, with no warranty.\n'
                    'Source: https://github.com/Aryan-mor/sushi-study-app',
                useRootNavigator: true,
              ),
              child: Text(context.localized.aboutLicenses),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute<void>(builder: (_) => const SushiDmcaPage()),
              ),
              child: Text(SushiDmcaCopy.of(context).button),
            ),
            FilledButton.tonal(
              onPressed: () => _openSupport(context),
              child: Text(SushiDmcaCopy.of(context).support),
            ),
          ],
        ),
      ].addInBetween(const SizedBox(height: 16)),
    );
  }
}
