import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xid/xid.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/account_model.dart';
import 'package:fladder/models/credentials_model.dart';
import 'package:fladder/providers/shared_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/sushi/sushi_config.dart';

const kSushiLocalServerId = 'sushi-local';
const kSushiLocalUrl = 'sushi://local';

/// Policy is not persisted on [AccountModel] (`includeFromJson: false`). Re-attach on every load
/// so Fladder's Synced tab / download button stay on (docs/05 §7, docs/10 Q5).
const sushiLocalDownloadPolicy = UserPolicy(
  enableContentDownloading: true,
  authenticationProviderId: 'sushi',
  passwordResetProviderId: 'sushi',
);

AccountModel sushiWithDownloadPolicy(AccountModel account) =>
    account.copyWith(policy: sushiLocalDownloadPolicy);

/// Local shell account — no HTTP API. Lets Fladder nav/auth guards pass after TDLib Ready.
Future<AccountModel> sushiEnsureLocalAccount(WidgetRef ref, {String? displayName}) async {
  assert(SushiConfig.isEnabled);
  final existing = ref.read(sharedUtilityProvider).getMostRecentAccount();
  if (existing != null && existing.credentials.serverId == kSushiLocalServerId) {
    final updated = sushiWithDownloadPolicy(existing.copyWith(lastUsed: DateTime.now()));
    await ref.read(sharedUtilityProvider).addAccount(updated);
    ref.read(userProvider.notifier).updateUser(updated);
    return updated;
  }

  final account = sushiWithDownloadPolicy(AccountModel(
    name: displayName?.trim().isNotEmpty == true ? displayName!.trim() : 'Sushi',
    id: Xid().toString(),
    avatar: '',
    lastUsed: DateTime.now(),
    authMethod: Authentication.autoLogin,
    credentials: CredentialsModel.internal(
      token: 'sushi-local',
      url: kSushiLocalUrl,
      serverName: 'Sushi',
      serverId: kSushiLocalServerId,
      deviceId: Xid().toString(),
    ),
  ));
  await ref.read(sharedUtilityProvider).addAccount(account);
  ref.read(userProvider.notifier).updateUser(account);
  return account;
}

bool sushiIsLocalAccount(AccountModel? account) {
  if (account == null) return false;
  return account.credentials.serverId == kSushiLocalServerId ||
      account.credentials.url.startsWith('sushi://');
}
