import 'dart:io';

import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/screens/shared/fladder_notification_overlay.dart';
import 'package:fladder/screens/shared/media/components/poster_overlays.dart';
import 'package:fladder/sushi/personal/sushi_personal.dart';
import 'package:fladder/sushi/personal/sushi_personal_transport.dart';
import 'package:fladder/sushi/personal/sushi_personal_thumbs.dart';
import 'package:fladder/sushi/sushi_config.dart';
import 'package:fladder/sushi/sushi_list_pb.dart';
import 'package:fladder/theme.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/focus_provider.dart';
import 'package:fladder/util/item_base_model/play_item_helpers.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/router_extension.dart';
import 'package:fladder/widgets/navigation_scaffold/components/settings_user_icon.dart';
import 'package:fladder/widgets/shared/ensure_visible.dart';
import 'package:fladder/widgets/shared/grid_focus_traveler.dart';
import 'package:fladder/widgets/shared/item_actions.dart';
import 'package:fladder/widgets/shared/modal_bottom_sheet.dart';
import 'package:fladder/widgets/shared/status_card.dart';

/// My videos (ADR 0037 §6): the videos this person sent to main-bot. Reached from the side menu
/// only — never on Home, never in Continue Watching.
@RoutePage()
class SushiMyVideosScreen extends ConsumerStatefulWidget {
  const SushiMyVideosScreen({super.key});

  @override
  ConsumerState<SushiMyVideosScreen> createState() => _SushiMyVideosScreenState();
}

class _SushiMyVideosScreenState extends ConsumerState<SushiMyVideosScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(sushiMyVideosProvider.notifier).refresh());
  }

  /// Same chrome as a film or series card (ADR 0038): long press opens the bottom sheet,
  /// right click opens the cursor menu. Actions stay Play, Share, Delete.
  List<ItemAction> _actions(BuildContext context, SushiPersonalVideo video) => [
        ItemActionButton(
          icon: const Icon(IconsaxPlusLinear.play),
          label: Text(context.localized.sushiMyVideosPlay),
          action: () => _play(video),
        ),
        ItemActionButton(
          icon: const Icon(IconsaxPlusLinear.send_2),
          label: Text(context.localized.share),
          action: () => _share(video),
        ),
        ItemActionButton(
          icon: const Icon(IconsaxPlusLinear.trash),
          label: Text(context.localized.delete),
          action: () => _delete(video),
        ),
      ];

  Future<void> _showActionSheet(SushiPersonalVideo video) async {
    if (!mounted) return;
    await showBottomSheetPill(
      context: context,
      content: (sheetContext, scrollController) => ListView(
        shrinkWrap: true,
        controller: scrollController,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12).copyWith(top: 8),
            child: _VideoSheetPreview(video: video),
          ),
          const Divider(),
          ..._actions(sheetContext, video).listTileItems(sheetContext, useIcons: true),
        ],
      ),
    );
  }

  Future<void> _showActionMenu(SushiPersonalVideo video, Offset globalPos) async {
    if (!mounted) return;
    final position = RelativeRect.fromLTRB(globalPos.dx, globalPos.dy, globalPos.dx, globalPos.dy);
    await showMenu(
      context: context,
      position: position,
      items: _actions(context, video).popupMenuItems(useIcons: true),
    );
  }

  /// main-bot sends the person, on their Telegram account, a warning and the link.
  Future<void> _share(SushiPersonalVideo video) async {
    final ok = await sushiPersonalAction(personalId: video.personalId, action: SushiPersonalAction.share);
    if (!mounted) return;
    FladderSnack.show(
      ok ? context.localized.sushiMyVideosShareSent : context.localized.sushiMyVideosActionFailed,
      context: context,
    );
  }

  /// Asks once more, then ends this person's access. The video and everyone else's access stay.
  Future<void> _delete(SushiPersonalVideo video) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.localized.sushiMyVideosDeleteTitle),
        content: Text(context.localized.sushiMyVideosDeleteBody(video.title)),
        actions: [
          // Cancel is focused first: a stray OK on a remote must not delete.
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.localized.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.localized.delete),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    final ok = await sushiPersonalAction(personalId: video.personalId, action: SushiPersonalAction.delete);
    if (!mounted) return;
    if (!ok) {
      FladderSnack.show(context.localized.sushiMyVideosActionFailed, context: context);
      return;
    }
    await ref.read(sushiMyVideosProvider.notifier).removeLocal(video.personalId);
  }

  Future<void> _play(SushiPersonalVideo video) async {
    await sushiPersonalVideoToItem(video).play(context, ref);
    // Back from the player: progress (and a freshly cached thumbnail) should show.
    if (mounted) await ref.read(sushiMyVideosProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sushiMyVideosProvider);
    final layout = AdaptiveLayout.of(context);
    // Tablet, desktop and TV draw the side rail over the page: start after it, like the libraries.
    return Padding(
      padding: EdgeInsetsDirectional.only(start: layout.sideBarWidth),
      child: Scaffold(
        body: RefreshIndicator(
          onRefresh: () => ref.read(sushiMyVideosProvider.notifier).refresh(),
          child: LayoutBuilder(
            builder: (context, constraints) => CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                const _TopBar(),
                ..._content(context, state, constraints.maxWidth),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context, SushiMyVideosState state, double maxWidth) {
    if (!state.loaded) {
      return [
        state.failed
            ? SliverToBoxAdapter(child: _Message(text: context.localized.sushiMyVideosLoadFailed, onRetry: _retry))
            : const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator())),
      ];
    }
    if (state.videos.isEmpty) return const [SliverToBoxAdapter(child: _EmptyHint())];
    final padding = MediaQuery.paddingOf(context);
    // The Movies grid's sizing, with landscape cells: a Telegram thumbnail is 16:9, not a poster.
    final posterScale = ref.watch(clientSettingsProvider.select((value) => value.posterSize));
    final cellTarget = AdaptiveLayout.poster(context).gridRatio * posterScale * _landscapeScale;
    final textScaler = MediaQuery.textScalerOf(context);
    final theme = Theme.of(context);
    final textHeight = textScaler.scale(theme.textTheme.titleMedium?.fontSize ?? 16) * 1.5 +
        textScaler.scale(theme.textTheme.titleSmall?.fontSize ?? 14) * 1.5;
    final width = maxWidth - padding.horizontal - 2 * _gridPadding;
    final columns = (width / cellTarget).floor().clamp(2, 10);
    final cellWidth = (width - (columns - 1) * _spacing) / columns;
    return [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(
          padding.left + _gridPadding,
          8,
          padding.right + _gridPadding,
          padding.bottom + 32,
        ),
        sliver: ValueListenableBuilder<int>(
          valueListenable: sushiPersonalThumbsVersion,
          builder: (context, _, __) => GridFocusTraveler(
            itemCount: state.videos.length,
            crossAxisCount: columns,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: _spacing,
              mainAxisSpacing: _spacing,
              mainAxisExtent: cellWidth * 9 / 16 + textHeight,
            ),
            itemBuilder: (other, selectedIndex, index) {
              final video = state.videos[index];
              return _VideoCard(
                key: ValueKey(video.personalId),
                video: video,
                onTap: () => _play(video),
                onLongPress: () => _showActionSheet(video),
                onSecondaryTap: (pos) => _showActionMenu(video, pos),
                onFocusChanged: (focus) {
                  if (focus) other.ensureVisible();
                },
              );
            },
          ),
        ),
      ),
    ];
  }

  void _retry() => ref.read(sushiMyVideosProvider.notifier).refresh();
}

/// A landscape cell is this much wider than a Movies poster cell at the same poster size.
const _landscapeScale = 1.6;
const _spacing = 8.0;
const _gridPadding = 8.0;

/// The Movies poster card (PosterWidget), landscape: image, then title and duration under it.
class _VideoCard extends StatelessWidget {
  const _VideoCard({
    super.key,
    required this.video,
    required this.onTap,
    required this.onLongPress,
    required this.onSecondaryTap,
    this.onFocusChanged,
  });

  final SushiPersonalVideo video;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final void Function(Offset globalPosition) onSecondaryTap;
  final ValueChanged<bool>? onFocusChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = FladderTheme.smallShape.borderRadius;
    final progress = (video.durationS > 0 && !video.done) ? video.positionS * 100 / video.durationS : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: FocusButton(
            onTap: onTap,
            onLongPress: onLongPress,
            onSecondaryTapDown: (details) => onSecondaryTap(details.globalPosition),
            onFocusChanged: onFocusChanged,
            child: Container(
              decoration: BoxDecoration(borderRadius: radius, color: theme.colorScheme.surfaceContainer),
              foregroundDecoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(width: 1, color: Colors.white.withAlpha(45)),
              ),
              child: ClipRRect(borderRadius: radius, child: _Thumb(personalId: video.personalId)),
            ),
            overlays: [
              if (video.done)
                IgnorePointer(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: StatusCard(
                      color: theme.colorScheme.primaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(Icons.check_rounded, size: 20, color: theme.colorScheme.primary),
                      ),
                    ),
                  ),
                ),
              BottomOverlaysContainer(
                showFavourite: false,
                showProgress: true,
                progress: progress,
                itemType: FladderItemType.movie,
                progressPadding: const EdgeInsets.all(5),
              ),
            ],
          ),
        ),
        Text(
          video.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        Opacity(
          opacity: 0.65,
          child: Text(
            video.durationS > 0 ? _formatDuration(video.durationS) : '',
            maxLines: 1,
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

/// The Movies top bar without search and library buttons: back (not on a remote, where Back is
/// the back button), the page title where the search bar sits, and the profile on phones.
class _TopBar extends StatelessWidget {
  const _TopBar();

  static const _toolbarHeight = 55.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SliverAppBar(
      floating: true,
      automaticallyImplyLeading: false,
      primary: true,
      elevation: 5,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      backgroundColor: Colors.transparent,
      titleSpacing: 4,
      toolbarHeight: _toolbarHeight + 8,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [theme.colorScheme.surface.withAlpha(255), theme.colorScheme.surface.withAlpha(0)],
          ),
        ),
      ),
      title: SizedBox(
        height: _toolbarHeight,
        child: Row(
          spacing: 2,
          children: [
            const SizedBox(width: 2),
            if (AdaptiveLayout.inputDeviceOf(context) != InputDevice.dPad)
              if (context.router.backButton() case final back?)
                Center(
                  child: SizedBox.square(
                    dimension: _toolbarHeight,
                    child: Card(elevation: 0, child: back),
                  ),
                ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                context.localized.sushiMyVideos,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (AdaptiveLayout.layoutModeOf(context) == LayoutMode.single)
          const SizedBox.square(dimension: _toolbarHeight - 3.0, child: SettingsUserIcon()),
        const SizedBox(width: 12),
      ],
    );
  }
}

/// Same header row as [ItemBottomSheetPreview], with the cached landscape thumb.
class _VideoSheetPreview extends StatelessWidget {
  const _VideoSheetPreview({required this.video});

  final SushiPersonalVideo video;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Card(
          child: SizedBox(
            height: 90,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: FladderTheme.smallShape.borderRadius,
                child: _Thumb(personalId: video.personalId),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                video.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge,
              ),
              if (video.durationS > 0)
                Opacity(
                  opacity: 0.75,
                  child: Text(
                    _formatDuration(video.durationS),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The cached thumbnail, or a placeholder until this device has played the video.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.personalId});

  final int personalId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File?>(
      future: sushiPersonalThumbFile(personalId),
      builder: (context, snap) {
        final file = snap.data;
        if (file != null) {
          return Image.file(
            file,
            fit: BoxFit.cover,
            // A rewritten file keeps its path; the version bump must still repaint it.
            key: ValueKey('${file.path}#${sushiPersonalThumbsVersion.value}'),
            errorBuilder: (context, _, __) => const _Placeholder(),
          );
        }
        return const _Placeholder();
      },
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(child: Icon(IconsaxPlusLinear.video_play, size: 40, color: scheme.onSurfaceVariant)),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  Future<void> _openBot() async {
    final uri = Uri.parse(SushiConfig.mainBotAppCodeUrl('upload'));
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 48),
          Icon(IconsaxPlusLinear.video_add, size: 64, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            context.localized.sushiMyVideosEmpty,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 24),
          Center(
            child: FilledButton.icon(
              autofocus: true,
              onPressed: _openBot,
              icon: const Icon(IconsaxPlusLinear.send_2),
              label: Text(context.localized.sushiMyVideosSend),
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.onRetry});

  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 48),
          Text(text, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Center(
            child: OutlinedButton(onPressed: onRetry, child: Text(context.localized.retry)),
          ),
        ],
      ),
    );
  }
}

String _formatDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}
