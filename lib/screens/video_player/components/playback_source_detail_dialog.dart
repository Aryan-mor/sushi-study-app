import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import 'package:fladder/models/items/item_stream_model.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/playback/playback_model.dart';

MediaStreamsModel? mediaStreamsForPlayback(PlaybackModel? model) {
  if (model == null) return null;
  if (model.mediaStreams != null) return model.mediaStreams;
  final item = model.item;
  if (item is ItemStreamModel) return item.mediaStreams;
  return null;
}

/// Short label for the playing file (Ox/Jellyfin media source): quality name or derived resolution.
String? playbackFileQualityLabel(MediaStreamsModel? ms) {
  if (ms == null) return null;
  final v = ms.currentVersionStream;
  if (v == null) return ms.mediaInfoTag?.trim().isNotEmpty == true ? ms.mediaInfoTag : null;
  final name = v.name.trim();
  if (name.isNotEmpty) return name;
  final detailed = v.detailedResolutionLabel.trim();
  if (detailed.isNotEmpty && detailed != 'Unknown') return detailed;
  return ms.mediaInfoTag?.trim().isNotEmpty == true ? ms.mediaInfoTag : null;
}

Future<void> showPlaybackSourceDetailDialog(BuildContext context, MediaStreamsModel? ms) async {
  if (ms == null) return;
  final label = playbackFileQualityLabel(ms);
  final version = ms.currentVersionStream;
  final video = ms.videoStreams.firstOrNull;

  final techLines = <String>{
    if (version != null && version.detailedResolutionLabel.trim().isNotEmpty) version.detailedResolutionLabel,
    if (ms.resolutionText != null && ms.resolutionText!.trim().isNotEmpty) ms.resolutionText!,
    if (video != null) video.prettyName,
    if (ms.mediaInfoTag != null && ms.mediaInfoTag!.trim().isNotEmpty) ms.mediaInfoTag!,
  }.where((s) => s.trim().isNotEmpty).toList();

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(label ?? ''),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (techLines.isNotEmpty) ...[
              Text(
                'Technical details',
                style: Theme.of(ctx).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              SelectableText(techLines.join('\n')),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
