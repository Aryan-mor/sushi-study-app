import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/sushi/sushi_detail_state.dart';
import 'package:fladder/sushi/sushi_request_pb.dart';
import 'package:fladder/sushi/sushi_request_transport.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/widgets/shared/selectable_icon_button.dart';

/// The Request button (ADR 0014 §D2). Shown in place of the play button when a title has no
/// playable file — a wish for a movie or whole series we do not carry yet.
///
/// Once a request has gone in (this session or a previous one — [sushiRequestedProvider] is
/// persisted), it turns into a disabled "Requested" button. The "it's ready" news arrives later as
/// a main-bot Telegram DM, so there is nothing else to render here.
class SushiRequestButton extends ConsumerStatefulWidget {
  const SushiRequestButton({
    required this.tmdbId,
    required this.kind,
    this.prominent = false,
    this.onAlreadyAvailable,
    super.key,
  });

  /// TMDB id of the title.
  final int tmdbId;

  /// 1 movie, 2 series.
  final int kind;

  /// Big filled button (replaces play) vs. a compact icon button (an action row).
  final bool prominent;

  /// Called when the server says the title is already serveable — the caller should refetch so the
  /// play button can take over.
  final VoidCallback? onAlreadyAvailable;

  @override
  ConsumerState<SushiRequestButton> createState() => _SushiRequestButtonState();
}

class _SushiRequestButtonState extends ConsumerState<SushiRequestButton> {
  bool _busy = false;

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    final res = await sushiSendRequest(tmdbId: widget.tmdbId, kind: widget.kind);
    if (!mounted) return;
    setState(() => _busy = false);

    final l = context.localized;
    final requested = ref.read(sushiRequestedProvider.notifier);
    final String message;
    switch (res?.outcome) {
      case SushiRequestOutcome.accepted:
        message = l.sushiRequestSent;
        await requested.mark(widget.tmdbId, widget.kind);
      case SushiRequestOutcome.duplicate:
        message = l.sushiRequestDuplicate;
        await requested.mark(widget.tmdbId, widget.kind);
      case SushiRequestOutcome.alreadyAvailable:
        message = l.sushiRequestAvailableNow;
        await requested.clear(widget.tmdbId, widget.kind);
        widget.onAlreadyAvailable?.call();
      case SushiRequestOutcome.quotaExceeded:
        message = l.sushiRequestQuota;
      case SushiRequestOutcome.unspecified:
      case null:
        message = l.sushiRequestFailed;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final alreadyRequested =
        ref.watch(sushiRequestedProvider.select((s) => s.contains('${widget.tmdbId}:${widget.kind}')));
    final label = alreadyRequested ? context.localized.sushiRequested : context.localized.request;
    final icon = alreadyRequested ? IconsaxPlusLinear.tick_circle : IconsaxPlusLinear.add;
    final onPressed = (alreadyRequested || _busy) ? null : _submit;

    if (!widget.prominent) {
      return SelectableIconButton(
        onPressed: onPressed ?? () {},
        selected: alreadyRequested,
        refreshOnEnd: false,
        icon: icon,
        label: label,
      );
    }
    return FilledButton.icon(
      onPressed: onPressed,
      icon: _busy
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon),
      label: Text(label),
      style: FilledButton.styleFrom(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 20, vertical: 14),
      ),
    );
  }
}
