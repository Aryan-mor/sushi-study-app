import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:fladder/sushi/sushi_env.dart';
import 'package:fladder/screens/settings/settings_list_tile.dart';
import 'package:fladder/screens/settings/widgets/settings_label_divider.dart';
import 'package:fladder/screens/settings/widgets/settings_list_group.dart';
import 'package:fladder/util/localization_helper.dart';

/// OX-only profile section: delete server account (Settings → Profile).
List<Widget> sushiProfileDeleteAccountGroup(BuildContext context) {
  return settingsListGroup(
    context,
    SettingsLabelDivider(label: context.localized.sushiDeleteAccountSection),
    [
      SettingsListTile(
        label: Text(
          context.localized.sushiDeleteAccountTitle,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
        subLabel: Text(context.localized.sushiDeleteAccountSubtitle),
        onTap: () => _confirmDeleteAccount(context),
      ),
    ],
  );
}

/// Account deletion happens in a conversation with the main bot over Telegram — Sushi has no
/// HTTP backend of its own to call. This just confirms, then hands off to Telegram.
Future<void> _confirmDeleteAccount(BuildContext context) async {
  final loc = context.localized;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(loc.sushiDeleteAccountDialogTitle),
      content: Text(loc.sushiDeleteAccountDialogBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(loc.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
            foregroundColor: Theme.of(ctx).colorScheme.onError,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(loc.sushiDeleteAccountConfirm),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  final opened = await sushiOpenBotDeleteAccountLink();
  if (opened || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(loc.sushiDeleteAccountFailed)),
  );
}

/// Opens the main-bot delete-account deep link.
Future<bool> sushiOpenBotDeleteAccountLink() async {
  final link = SushiEnv.telegramBotDeleteAccountLink;
  if (link == null) return false;
  final uri = Uri.parse(link);
  if (!await canLaunchUrl(uri)) return false;
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
