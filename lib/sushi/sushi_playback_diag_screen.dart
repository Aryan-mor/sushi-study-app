import 'dart:convert';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/sushi/sushi_playback_diag_runner.dart';
import 'package:fladder/util/localization_helper.dart';

@RoutePage()
class SushiPlaybackDiagScreen extends ConsumerStatefulWidget {
  const SushiPlaybackDiagScreen({super.key});

  @override
  ConsumerState<SushiPlaybackDiagScreen> createState() => _SushiPlaybackDiagScreenState();
}

class _SushiPlaybackDiagScreenState extends ConsumerState<SushiPlaybackDiagScreen> {
  SushiPlaybackDiagRunner? _runner;
  _DiagPhase _phase = _DiagPhase.idle;
  String _statusKey = 'sushiPlaybackDiagStatusIdle';
  String? _report;

  @override
  void dispose() {
    _runner?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    if (_phase == _DiagPhase.running) return;
    setState(() {
      _phase = _DiagPhase.running;
      _report = null;
      _statusKey = 'sushiPlaybackDiagStatusStarting';
    });

    final runner = SushiPlaybackDiagRunner(ref);
    _runner = runner;
    try {
      final text = await runner.run(onPhase: (phase) {
        if (!mounted) return;
        setState(() => _statusKey = _phaseToStatusKey(phase));
      });
      if (!mounted || _phase != _DiagPhase.running) return;
      final failed = text.contains('"phaseErrors"');
      setState(() {
        _report = text;
        _phase = _DiagPhase.done;
        _statusKey = failed
            ? 'sushiPlaybackDiagStatusFailed'
            : 'sushiPlaybackDiagStatusDone';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _report = '{\n  "error": ${jsonEncode(e.toString())}\n}';
        _phase = _DiagPhase.done;
        _statusKey = 'sushiPlaybackDiagStatusFailed';
      });
    }
  }

  void _cancel() {
    _runner?.cancel();
    setState(() {
      _phase = _DiagPhase.idle;
      _statusKey = 'sushiPlaybackDiagStatusCancelled';
    });
  }

  Future<void> _copy() async {
    final text = _report;
    if (text == null || text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.localized.sushiPlaybackDiagCopied)),
    );
  }

  String _localizedStatus(BuildContext context) {
    final l10n = context.localized;
    return switch (_statusKey) {
      'sushiPlaybackDiagStatusStarting' => l10n.sushiPlaybackDiagStatusStarting,
      'sushiPlaybackDiagStatusCollecting' => l10n.sushiPlaybackDiagStatusCollecting,
      'sushiPlaybackDiagStatusProbing' => l10n.sushiPlaybackDiagStatusProbing,
      'sushiPlaybackDiagStatusPlayback' => l10n.sushiPlaybackDiagStatusPlayback,
      'sushiPlaybackDiagStatusWatching' => l10n.sushiPlaybackDiagStatusWatching,
      'sushiPlaybackDiagStatusDone' => l10n.sushiPlaybackDiagStatusDone,
      'sushiPlaybackDiagStatusFailed' => l10n.sushiPlaybackDiagStatusFailed,
      'sushiPlaybackDiagStatusCancelled' => l10n.sushiPlaybackDiagStatusCancelled,
      _ => l10n.sushiPlaybackDiagStatusIdle,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.localized;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.sushiPlaybackDiagTitle),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.sushiPlaybackDiagIntro,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    _phase == _DiagPhase.running ? IconsaxPlusLinear.timer_1 : IconsaxPlusLinear.info_circle,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_localizedStatus(context))),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.dividerColor.withValues(alpha: 0.4)),
                  ),
                  child: Scrollbar(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(
                        _report ?? l10n.sushiPlaybackDiagPlaceholder,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          fontFamilyFallback: const ['Courier New', 'monospace'],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_phase == _DiagPhase.running)
                FilledButton.tonal(
                  onPressed: _cancel,
                  child: Text(l10n.sushiPlaybackDiagCancel),
                )
              else if (_phase == _DiagPhase.done)
                FilledButton(
                  onPressed: _copy,
                  child: Text(l10n.sushiPlaybackDiagCopy),
                )
              else
                FilledButton(
                  onPressed: _start,
                  child: Text(l10n.sushiPlaybackDiagStart),
                ),
              if (_phase == _DiagPhase.done) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _start,
                  child: Text(l10n.sushiPlaybackDiagRestart),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _phaseToStatusKey(String phase) => switch (phase) {
        'collecting_context' => 'sushiPlaybackDiagStatusCollecting',
        'probing_api' => 'sushiPlaybackDiagStatusProbing',
        'probing_playback' => 'sushiPlaybackDiagStatusPlayback',
        'watching_playback' => 'sushiPlaybackDiagStatusWatching',
        _ => 'sushiPlaybackDiagStatusStarting',
      };
}

enum _DiagPhase { idle, running, done }
