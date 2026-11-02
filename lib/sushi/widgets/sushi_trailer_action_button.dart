import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/sushi/providers/sushi_trailer_provider.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/sushi_media_streams.dart';
import 'package:fladder/sushi/widgets/sushi_enum_box.dart';
import 'package:fladder/sushi/widgets/sushi_trailer_player.dart';
import 'package:fladder/screens/details_screens/components/media_stream_information.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/widgets/shared/item_actions.dart';
import 'package:fladder/widgets/shared/selectable_icon_button.dart';

/// Detail play/trailer/version layout.
///
/// Order: Play, then file/version picker, then Trailer, then icon actions.
///
/// **Phone:** Play full width; under it a [Wrap]: quality, Trailer, icons pack
/// at intrinsic size (flex-wrap). Only spill to next line when they truly
/// do not fit — quality must not stretch full-bleed.
/// **Tablet/TV:** Play only. Version stays in [OverviewHeader]; Trailer is
/// placed immediately after that picker via [OverviewHeader.afterMediaStreams].
class SushiDetailPrimaryRow extends ConsumerWidget {
  final Widget? primary;
  final String itemId;
  final SushiKind kind;
  final String title;
  final MediaStreamHelper? versionHelper;

  /// Watch-later / menu icons — phone only, same [Wrap] as quality.
  final List<Widget> trailingActions;

  /// Same signal as the Resume label: playback progress or marked played.
  final bool engaged;

  /// When false, caller places Trailer after the version picker (tablet/TV).
  final bool inlineTrailer;

  const SushiDetailPrimaryRow({
    required this.itemId,
    required this.kind,
    required this.title,
    required this.primary,
    this.versionHelper,
    this.trailingActions = const [],
    this.engaged = false,
    this.inlineTrailer = true,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sushiTrailerStateProvider((itemId: itemId, kind: kind))).valueOrNull;
    final showTrailer =
        inlineTrailer && (state?.hasTrailer ?? false) && !(state?.watched ?? false) && !engaged;
    final isPhone = AdaptiveLayout.viewSizeOf(context) == ViewSize.phone;
    final showVersion = isPhone &&
        versionHelper != null &&
        sushiShowVersionStreamPicker(versionHelper!.mediaStream);
    final trailing = isPhone ? trailingActions : const <Widget>[];
    if (primary == null && !showTrailer && !showVersion && trailing.isEmpty) {
      return const SizedBox.shrink();
    }

    if (!isPhone) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          if (primary != null) primary!,
          if (showTrailer)
            SushiTrailerActionButton(itemId: itemId, kind: kind, title: title, compact: true),
        ],
      );
    }

    final secondary = showTrailer || showVersion || trailing.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        if (primary != null) primary!,
        if (secondary)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (showVersion) SushiVersionPickerButton(helper: versionHelper!),
              if (showTrailer)
                SushiTrailerActionButton(itemId: itemId, kind: kind, title: title, compact: true),
              ...trailing,
            ],
          ),
      ],
    );
  }
}

/// Puts Trailer immediately above the last action (Movie info) once the title is watched or started.
List<ItemAction> sushiInsertWatchedTrailer(
  List<ItemAction> actions, {
  required SushiTrailerState? state,
  required void Function() onOpen,
  bool engaged = false,
}) {
  if (state == null || !state.hasTrailer || !(state.watched || engaged)) return actions;
  final trailer = ItemActionButton(
    icon: const Icon(IconsaxPlusLinear.video_play),
    label: const Text('Trailer'),
    action: onOpen,
  );
  if (actions.isEmpty) return [trailer];
  final next = [...actions];
  next.insert(next.length - 1, trailer);
  return next;
}

/// Secondary quality chip — intrinsic width so [Wrap] can pack Trailer / icons beside it.
class SushiVersionPickerButton extends StatelessWidget {
  final MediaStreamHelper helper;

  const SushiVersionPickerButton({required this.helper, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = helper.mediaStream.currentVersionStream;
    final label = current != null
        ? sushiVersionStreamLabel(current, l10n: context.localized, siblings: helper.mediaStream.versionStreams)
        : '';
    return SizedBox(
      height: 48,
      child: SushiEnumBox(
        secondary: true,
        currentWidget: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            Icon(IconsaxPlusLinear.video_square, color: theme.colorScheme.onSurface),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        itemBuilder: (context) => helper.mediaStream.versionStreams
            .mapIndexed(
              (index, e) => ItemActionButton(
                selected: helper.mediaStream.currentVersionStream == e,
                label: Text(sushiVersionStreamLabel(
                  e,
                  l10n: context.localized,
                  siblings: helper.mediaStream.versionStreams,
                )),
                action: () {
                  helper.onItemChanged?.call(
                    helper.mediaStream.copyWith(versionStreamIndex: e.index),
                  );
                },
              ),
            )
            .toList(),
      ),
    );
  }
}

/// Shown after the file/version picker while unwatched + YouTube key exists.
class SushiTrailerActionButton extends ConsumerWidget {
  final String itemId;
  final SushiKind kind;
  final String title;

  /// Compact [SelectableIconButton] for tablet/TV row beside Play.
  final bool compact;

  const SushiTrailerActionButton({
    required this.itemId,
    required this.kind,
    required this.title,
    this.compact = false,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trailer = ref.watch(sushiTrailerStateProvider((itemId: itemId, kind: kind)));
    final state = trailer.valueOrNull;
    if (state == null || !state.hasTrailer || state.watched) {
      return const SizedBox.shrink();
    }
    void open() => SushiTrailerPlayer.open(
          context,
          youtubeKey: state.trailerKey,
          title: title,
        );
    if (compact) {
      return SelectableIconButton(
        selected: false,
        icon: IconsaxPlusLinear.video_play,
        label: 'Trailer',
        onPressed: open,
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: scheme.onSurface,
        );
    const radius = BorderRadius.all(Radius.circular(16));
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: open,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Trailer', style: textStyle),
              const SizedBox(width: 10),
              Icon(IconsaxPlusLinear.video_play, color: scheme.onSurface.withValues(alpha: 0.65)),
            ],
          ),
        ),
      ),
    );
  }
}
