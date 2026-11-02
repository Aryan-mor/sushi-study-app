import 'dart:async';

import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/l10n/generated/app_localizations.dart';
import 'package:fladder/sushi/sushi_account_playback_pref.dart';
import 'package:fladder/sushi/sushi_dpad_text_field.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/sushi_pending_route.dart';
import 'package:fladder/sushi/sushi_search_transport.dart';
import 'package:fladder/sushi/sushi_splash_brand.dart';
import 'package:fladder/sushi/sushi_taste_local.dart';
import 'package:fladder/sushi/sushi_taste_pb.dart';
import 'package:fladder/sushi/sushi_taste_transport.dart';
import 'package:fladder/theme.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/focus_provider.dart';
import 'package:fladder/util/localization_helper.dart';

enum _TasteStep {
  watchKind,
  genres,
  titles,
  people,
  quality,
  audio,
  subtitle,
  subs,
}

/// First-run / profile taste wizard. TV-friendly D-pad focus throughout.
@RoutePage()
class SushiTasteWizardScreen extends ConsumerStatefulWidget {
  const SushiTasteWizardScreen({
    this.fromProfile = false,
    super.key,
  });

  final bool fromProfile;

  @override
  ConsumerState<SushiTasteWizardScreen> createState() =>
      _SushiTasteWizardScreenState();
}

class _SushiTasteWizardScreenState
    extends ConsumerState<SushiTasteWizardScreen> {
  static const _salmon = Color(0xFFE37A42);

  bool _loading = true;
  bool _saving = false;
  /// True only while Done/Skip is leaving the wizard. Remote Back must not treat that pop as a step back.
  bool _leaving = false;
  String? _error;

  _TasteStep _step = _TasteStep.watchKind;
  final List<_TasteStep> _history = [];

  String _watchKind = '';
  final Set<String> _genres = {};
  final Set<String> _likedTitleKeys = {}; // "id:kind"
  final Map<String, SushiTasteTitle> _likedTitleByKey = {};
  final Set<int> _likedPeople = {};
  final Map<int, SushiTastePerson> _personById = {};
  int _maxHeight = 0;
  String _audio = '';
  String _subtitleLang = '';

  /// Saved lang from the profile load. List order uses this, not the tap in progress.
  String _pinnedSubtitleLang = '';
  String _subs = '';

  List<SushiRow> _seedTitles = const [];
  List<SushiTastePerson> _seedPeople = const [];
  List<SushiRow> _titleHits = const [];
  List<SushiTastePerson> _personHits = const [];
  int _titleSeedPage = 0;
  bool _titleSeedsMore = true;
  bool _titleSeedsLoading = false;
  int _personSeedPage = 0;
  bool _personSeedsMore = true;
  bool _personSeedsLoading = false;
  String _titleQuery = '';
  String _personQuery = '';
  String _subtitleQuery = '';
  bool _titleSearchLoading = false;
  bool _personSearchLoading = false;

  final _titleSearchCtrl = TextEditingController();
  final _personSearchCtrl = TextEditingController();
  final _subtitleSearchCtrl = TextEditingController();
  Timer? _titleDebounce;
  Timer? _personDebounce;

  bool get _fa => Localizations.localeOf(context).languageCode == 'fa';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _titleDebounce?.cancel();
    _personDebounce?.cancel();
    _titleSearchCtrl.dispose();
    _personSearchCtrl.dispose();
    _subtitleSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await sushiFetchTaste();
    await sushiLoadAccountPlaybackPref();
    if (!mounted) return;
    _subs = switch (sushiAccountPlaybackPref.subs) {
      SushiSubsPref.on => 'on',
      SushiSubsPref.off => 'off',
      SushiSubsPref.unset => '',
    };
    if (res != null) {
      _applyRes(res);
    }
    // First run must not look pre-answered. Skip applies fa / 1080 / original; a tap is a real choice.
    if (!widget.fromProfile) {
      _maxHeight = 0;
      _audio = '';
      _subtitleLang = '';
      _pinnedSubtitleLang = '';
      _subs = '';
    }
    // Null = old apid / offline: still walk the wizard; save retries against the live server.
    _step = _firstStep();
    setState(() {
      _loading = false;
      _error = res == null
          ? (_fa
              ? 'سرور سلیقه هنوز جواب نداد — می‌تونی ادامه بدی، آخر ذخیره می‌شه.'
              : 'Taste server did not answer yet — you can continue; we save at the end.')
          : null;
    });
  }

  void _applyRes(SushiTasteRes res) {
    _watchKind = res.watchKind;
    _genres
      ..clear()
      ..addAll(res.genres);
    _likedTitleKeys.clear();
    _likedTitleByKey.clear();
    for (final t in res.likedTitles) {
      final key = '${t.tmdbId}:${t.kind}';
      _likedTitleKeys.add(key);
      _likedTitleByKey[key] = t;
    }
    _likedPeople
      ..clear()
      ..addAll(res.likedPeople);
    _maxHeight = res.maxHeight;
    _audio = res.audio;
    _subtitleLang = res.subtitleLang;
    _pinnedSubtitleLang = res.subtitleLang.trim().toLowerCase();
    if (res.subs == 'on' || res.subs == 'off') {
      _subs = res.subs;
    }
    // Server prepends liked cards on read — keep that order; do not re-sort on later taps.
    _seedTitles = res.seedTitles;
    _seedPeople = res.seedPeople;
    for (final p in _seedPeople) {
      _personById[p.tmdbId] = p;
    }
  }

  _TasteStep _firstStep() => _TasteStep.watchKind;

  List<_TasteStep> get _activeSteps {
    final steps = <_TasteStep>[
      _TasteStep.watchKind,
      _TasteStep.genres,
      _TasteStep.titles,
      _TasteStep.people,
    ];
    steps.add(_TasteStep.quality);
    // Subtitle lang, then with/without. Dub only after they pick Persian (skip defaults to fa).
    steps.add(_TasteStep.subtitle);
    steps.add(_TasteStep.subs);
    if (sushiSubtitleLangIsPersian(_subtitleLang)) {
      steps.add(_TasteStep.audio);
    }
    return steps;
  }

  /// Playback steps stay blank until a tap. Skip is the only path that writes the default.
  bool get _mustChoose => switch (_step) {
        _TasteStep.quality => _maxHeight == 0,
        _TasteStep.subtitle => _subtitleLang.trim().isEmpty,
        _TasteStep.subs => _subs != 'on' && _subs != 'off',
        _TasteStep.audio => _audio.isEmpty,
        _ => false,
      };

  void _goNext() {
    if (_mustChoose) return;
    final steps = _activeSteps;
    final idx = steps.indexOf(_step);
    if (idx < 0 || idx >= steps.length - 1) {
      unawaited(_finish());
      return;
    }
    _history.add(_step);
    setState(() => _step = steps[idx + 1]);
    if (_step == _TasteStep.titles) {
      unawaited(_refreshTitleSeeds());
    } else if (_step == _TasteStep.people) {
      unawaited(_refreshPersonSeeds());
    }
  }

  void _goBack() {
    if (_history.isEmpty || _saving) return;
    setState(() => _step = _history.removeLast());
  }

  Future<void> _refreshTitleSeeds({bool append = false}) async {
    if (_titleSeedsLoading) return;
    if (append && !_titleSeedsMore) return;
    final page = append ? _titleSeedPage + 1 : 1;
    setState(() => _titleSeedsLoading = true);
    final res = await sushiFetchTaste(watchKind: _watchKind, seedPage: page);
    if (!mounted) return;
    if (res == null) {
      setState(() {
        _titleSeedsLoading = false;
        if (!append && _seedTitles.isEmpty) {
          _error = _fa
              ? 'لیست فیلم نیومد. دوباره امتحان کن.'
              : 'Could not load titles. Try again.';
        }
      });
      return;
    }
    setState(() {
      if (append) {
        final seen = {
          for (final s in _seedTitles) '${s.tmdbId}:${sushiKindToWire(s.kind)}'
        };
        _seedTitles = [
          ..._seedTitles,
          ...res.seedTitles
              .where((s) => seen.add('${s.tmdbId}:${sushiKindToWire(s.kind)}')),
        ];
      } else {
        // Server already puts saved picks first; keep local search-pins at the end.
        final fresh = res.seedTitles;
        final freshKeys = {
          for (final s in fresh) '${s.tmdbId}:${sushiKindToWire(s.kind)}'
        };
        final pinned = _seedTitles.where((s) {
          final key = '${s.tmdbId}:${sushiKindToWire(s.kind)}';
          return _likedTitleKeys.contains(key) && !freshKeys.contains(key);
        });
        _seedTitles = [...fresh, ...pinned];
      }
      _titleSeedPage = page;
      _titleSeedsMore = res.seedTitles.length >= 20;
      _titleSeedsLoading = false;
      if (_seedTitles.isNotEmpty) _error = null;
    });
  }

  /// Unset playback picks. Chosen values stay.
  void _applyUnsetDefaults() {
    if (_subtitleLang.trim().isEmpty) _subtitleLang = 'fa';
    if (_subs != 'on' && _subs != 'off') _subs = 'on';
    if (_maxHeight == 0) _maxHeight = 1080;
    if (_audio.trim().isEmpty) _audio = 'original';
  }

  Future<void> _finish() async {
    _applyUnsetDefaults();
    setState(() => _saving = true);
    final titles = _likedTitleByKey.values.toList();
    // Non-Persian subtitle → original audio only (no dub default).
    final audio =
        sushiSubtitleLangIsPersian(_subtitleLang) ? _audio : 'original';
    final res = await sushiSaveTaste(
      watchKind: _watchKind,
      genres: _genres.toList(),
      likedTitles: titles,
      likedPeople: _likedPeople.toList(),
      maxHeight: _maxHeight,
      audio: audio,
      subtitleLang: _subtitleLang,
      subs: _subs,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (res == null) {
      setState(() {
        _error =
            _fa ? 'ذخیره نشد. دوباره امتحان کن.' : 'Save failed. Try again.';
      });
      return;
    }
    await sushiSaveAccountPlaybackPref(
      SushiAccountPlaybackPref.fromWire(
          audio, _maxHeight, _subtitleLang, _subs),
    );
    await sushiSetLocalTasteComplete(true);
    if (!mounted) return;
    _leaveTaste();
  }

  /// Close the wizard. Remote Back stays a step back until this runs.
  void _leaveTaste() {
    if (!mounted || _leaving) return;
    setState(() => _leaving = true);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (widget.fromProfile) {
        context.router.pop();
        return;
      }
      await sushiNavigateAfterLogin(context, ref, skipTasteCheck: true);
    });
  }

  bool get _wideNav => AdaptiveLayout.viewSizeOf(context) != ViewSize.phone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dPad = AdaptiveLayout.inputDeviceOf(context) == InputDevice.dPad;

    return PopScope(
      canPop: _leaving,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _leaving || _saving || _loading) return;
        _goBack();
      },
      child: Scaffold(
        backgroundColor: SushiSplashBrand.splashBackground,
        body: SafeArea(
          child: Stack(
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 48, 20, 16),
                    child: _loading
                        ? const Center(
                            child: CircularProgressIndicator(color: _salmon))
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: _stepCentersContent
                                    ? _centeredStepBlock(theme, dPad)
                                    : Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          _stepHeader(theme),
                                          const SizedBox(height: 20),
                                          Expanded(
                                            child: KeyedSubtree(
                                              key: ValueKey(_step),
                                              child: _buildStepBody(dPad),
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                              if (!_wideNav) ...[
                                const SizedBox(height: 12),
                                _footer(dPad),
                              ],
                            ],
                          ),
                  ),
                ),
              ),
              Positioned(
                top: 4,
                right: 8,
                child: TextButton(
                  onPressed: _saving || _loading ? null : () => unawaited(_finish()),
                  child: Text(
                    _fa ? 'رد کردن' : 'Skip',
                    style: const TextStyle(
                      color: _salmon,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Title + caption + choices as one block in the vertical center of the viewport.
  bool get _stepCentersContent =>
      _step == _TasteStep.watchKind ||
      _step == _TasteStep.quality ||
      _step == _TasteStep.audio ||
      _step == _TasteStep.subs;

  Widget _stepHeader(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _titleForStep(),
          style: theme.textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          _subtitleForStep(),
          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
          textAlign: TextAlign.center,
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!,
              style: TextStyle(color: theme.colorScheme.error),
              textAlign: TextAlign.center),
        ],
      ],
    );
  }

  Widget _centeredStepBlock(ThemeData theme, bool dPad) {
    final choices = Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _stepHeader(theme),
              const SizedBox(height: 36),
              KeyedSubtree(
                key: ValueKey(_step),
                child: _buildStepBody(dPad),
              ),
            ],
          ),
        ),
      ),
    );
    if (!_wideNav) return choices;
    return Row(
      textDirection: TextDirection.ltr,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _backRail(),
        const SizedBox(width: 12),
        Expanded(child: choices),
        const SizedBox(width: 12),
        _nextRail(),
      ],
    );
  }

  String _titleForStep() {
    if (_fa) {
      return switch (_step) {
        _TasteStep.watchKind => 'بیشتر چی می‌بینی؟',
        _TasteStep.genres => 'کدام ژانرها؟',
        _TasteStep.titles => 'چندتا از این‌ها رو دوست داری؟',
        _TasteStep.people => 'بازیگرهای محبوب',
        _TasteStep.quality => 'معمولاً چه کیفیتی می‌خوای؟',
        _TasteStep.audio => 'صدای اصلی یا دوبله؟',
        _TasteStep.subtitle => 'زبان زیرنویس',
        _TasteStep.subs => 'با زیرنویس یا بدون زیرنویس؟',
      };
    }
    return switch (_step) {
      _TasteStep.watchKind => 'What do you watch most?',
      _TasteStep.genres => 'Which genres?',
      _TasteStep.titles => 'Pick titles you like',
      _TasteStep.people => 'Favorite actors',
      _TasteStep.quality => 'Usual quality?',
      _TasteStep.audio => 'Original audio or dubbed?',
      _TasteStep.subtitle => 'Subtitle language',
      _TasteStep.subs => 'With subtitles or without?',
    };
  }

  String _subtitleForStep() {
    if (_fa) {
      return 'می‌تونی رد کنی — بعداً از پروفایل عوض می‌شه.';
    }
    return 'You can skip — change anytime in Profile.';
  }

  Widget _buildStepBody(bool dPad) {
    return switch (_step) {
      _TasteStep.watchKind => _watchKindStep(dPad),
      _TasteStep.genres => _genreStep(dPad),
      _TasteStep.titles => _titlesStep(dPad),
      _TasteStep.people => _peopleStep(dPad),
      _TasteStep.quality => _qualityStep(dPad),
      _TasteStep.audio => _audioStep(dPad),
      _TasteStep.subtitle => _subtitleStep(dPad),
      _TasteStep.subs => _subsStep(dPad),
    };
  }

  Widget _watchKindStep(bool dPad) {
    final items = [
      (
        value: 'movie',
        icon: IconsaxPlusLinear.video,
        label: _fa ? 'فیلم' : 'Movies'
      ),
      (
        value: 'series',
        icon: IconsaxPlusLinear.video_play,
        label: _fa ? 'سریال' : 'Series'
      ),
      (
        value: 'both',
        icon: Icons.local_movies_outlined,
        label: _fa ? 'هر دو' : 'Both'
      ),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 20),
          SizedBox(
            height: 72,
            child: _SelectCard(
              autoFocus: dPad && i == 0,
              selected: _watchKind == items[i].value,
              accent: _salmon,
              onTap: () => setState(() => _watchKind = items[i].value),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      items[i].icon,
                      size: 32,
                      color: _watchKind == items[i].value
                          ? _salmon
                          : Colors.white70,
                    ),
                    const SizedBox(width: 14),
                    Text(
                      items[i].label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _genreStep(bool dPad) {
    final genres = _tasteGenres;
    return _besideList(
      _choiceGrid(
        dPad: dPad,
        crossAxisCount:
            AdaptiveLayout.viewSizeOf(context) == ViewSize.phone ? 2 : 4,
        itemCount: genres.length,
        builder: (context, i) {
          final g = genres[i];
          final selected = _genres.contains(g.id);
          return _SelectCard(
            autoFocus: dPad && i == 0,
            selected: selected,
            accent: _salmon,
            onTap: () => setState(() {
              if (selected) {
                _genres.remove(g.id);
              } else {
                _genres.add(g.id);
              }
            }),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(g.icon,
                    size: 28, color: selected ? _salmon : Colors.white70),
                const SizedBox(height: 8),
                Text(
                  _fa ? g.fa : g.en,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<SushiRow> _titleRowsForQuery() {
    final q = _titleQuery.trim().toLowerCase();
    if (q.isEmpty) {
      return [
        ..._seedTitles,
        ..._titleHits.where((h) =>
            !_seedTitles.any((s) => s.tmdbId == h.tmdbId && s.kind == h.kind)),
      ];
    }
    // Searching: hide unrelated seeds; show local matches + remote hits.
    // Do not re-sort selected to top — jumping cards mid-tap is bad UX.
    final matchedSeeds =
        _seedTitles.where((s) => s.title.toLowerCase().contains(q));
    final out = <SushiRow>[..._titleHits];
    final seen = {
      for (final h in _titleHits) '${h.tmdbId}:${sushiKindToWire(h.kind)}'
    };
    for (final s in matchedSeeds) {
      final key = '${s.tmdbId}:${sushiKindToWire(s.kind)}';
      if (seen.add(key)) out.add(s);
    }
    return out;
  }

  Widget _titlesStep(bool dPad) {
    final searching = _titleQuery.trim().isNotEmpty;
    final rows = _titleRowsForQuery();
    final cols = AdaptiveLayout.viewSizeOf(context) == ViewSize.phone ? 3 : 5;
    return Column(
      children: [
        _searchField(
          controller: _titleSearchCtrl,
          hint: _fa ? 'جستجوی فیلم یا سریال…' : 'Search movies or series…',
          ltr: true,
          onChanged: (q) {
            setState(() => _titleQuery = q);
            _titleDebounce?.cancel();
            _titleDebounce = Timer(const Duration(milliseconds: 450),
                () => unawaited(_runTitleSearch(q)));
          },
        ),
        if (_titleSearchLoading) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(
              color: _salmon, minHeight: 2, backgroundColor: Colors.white12),
        ],
        const SizedBox(height: 12),
        Expanded(
          child: _besideList(
            rows.isEmpty && (_titleSeedsLoading || _titleSearchLoading)
                ? const Center(child: CircularProgressIndicator(color: _salmon))
                : rows.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              searching
                                  ? (_fa ? 'چیزی پیدا نشد.' : 'No matches.')
                                  : (_fa
                                      ? 'هنوز پوستری نیست. سرچ کن یا دوباره بگیر.'
                                      : 'No posters yet. Search or retry.'),
                              style: const TextStyle(color: Colors.white70),
                              textAlign: TextAlign.center,
                            ),
                            if (!searching) ...[
                              const SizedBox(height: 12),
                              TextButton(
                                onPressed: () =>
                                    unawaited(_refreshTitleSeeds()),
                                child: Text(_fa ? 'تلاش دوباره' : 'Retry',
                                    style: const TextStyle(color: _salmon)),
                              ),
                            ],
                          ],
                        ),
                      )
                    : NotificationListener<ScrollNotification>(
                        onNotification: (n) {
                          if (!searching &&
                              _titleSeedsMore &&
                              !_titleSeedsLoading &&
                              n.metrics.pixels >=
                                  n.metrics.maxScrollExtent - 280) {
                            unawaited(_refreshTitleSeeds(append: true));
                          }
                          return false;
                        },
                        child: GridView.builder(
                          primary: false,
                          itemCount: rows.length +
                              (_titleSeedsLoading && _titleSeedsMore ? 1 : 0),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: cols,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: 0.58,
                          ),
                          itemBuilder: (context, i) {
                            if (i >= rows.length) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(12),
                                  child: CircularProgressIndicator(
                                      color: _salmon, strokeWidth: 2),
                                ),
                              );
                            }
                            final row = rows[i];
                            final key =
                                '${row.tmdbId}:${sushiKindToWire(row.kind)}';
                            final selected = _likedTitleKeys.contains(key);
                            final url = row.poster.isEmpty
                                ? null
                                : sushiPosterUrl(row.poster, size: 'w342');
                            return _SelectCard(
                              autoFocus: dPad && i == 0,
                              selected: selected,
                              accent: _salmon,
                              onTap: () => setState(() {
                                if (selected) {
                                  _likedTitleKeys.remove(key);
                                  _likedTitleByKey.remove(key);
                                } else {
                                  _likedTitleKeys.add(key);
                                  _likedTitleByKey[key] = SushiTasteTitle(
                                    tmdbId: row.tmdbId,
                                    kind: sushiKindToWire(row.kind),
                                  );
                                  // Keep search picks on the base list after clearing the query.
                                  _pinTitleToSeeds(row);
                                }
                              }),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: url == null
                                          ? ColoredBox(
                                              color: Colors.white12,
                                              child: Center(
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.all(6),
                                                  child: _ltrText(
                                                    row.title,
                                                    textAlign: TextAlign.center,
                                                    maxLines: 3,
                                                    style: const TextStyle(
                                                        color: Colors.white70,
                                                        fontSize: 11),
                                                  ),
                                                ),
                                              ),
                                            )
                                          : CachedNetworkImage(
                                              imageUrl: url,
                                              fit: BoxFit.cover,
                                              placeholder: (_, __) =>
                                                  const ColoredBox(
                                                      color: Colors.white10),
                                              errorWidget: (_, __, ___) =>
                                                  ColoredBox(
                                                color: Colors.white12,
                                                child: Center(
                                                  child: _ltrText(
                                                    row.title,
                                                    textAlign: TextAlign.center,
                                                    maxLines: 3,
                                                    style: const TextStyle(
                                                        color: Colors.white70,
                                                        fontSize: 11),
                                                  ),
                                                ),
                                              ),
                                            ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  _ltrText(
                                    row.title,
                                    maxLines: 2,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      height: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ),
      ],
    );
  }

  Future<void> _runTitleSearch(String q) async {
    final trimmed = q.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _titleHits = const [];
        _titleSearchLoading = false;
      });
      return;
    }
    setState(() => _titleSearchLoading = true);
    final res = await sushiFetchSearch(query: trimmed);
    if (!mounted) return;
    // Ignore stale replies if the user kept typing.
    if (_titleQuery.trim() != trimmed) {
      setState(() => _titleSearchLoading = false);
      return;
    }
    final hits = <SushiRow>[
      ...?res?.rows,
      ...?res?.missing,
    ];
    setState(() {
      _titleHits = hits;
      _titleSearchLoading = false;
    });
  }

  Future<void> _refreshPersonSeeds({bool append = false}) async {
    if (_personSeedsLoading) return;
    if (append && !_personSeedsMore) return;
    final page = append ? _personSeedPage + 1 : 1;
    setState(() => _personSeedsLoading = true);
    final res = await sushiFetchTaste(personSeedPage: page);
    if (!mounted) return;
    if (res == null) {
      setState(() => _personSeedsLoading = false);
      return;
    }
    setState(() {
      if (append) {
        final seen = {for (final p in _seedPeople) p.tmdbId};
        _seedPeople = [
          ..._seedPeople,
          ...res.seedPeople.where((p) => seen.add(p.tmdbId)),
        ];
      } else {
        final fresh = res.seedPeople;
        final freshIds = {for (final p in fresh) p.tmdbId};
        final pinned = _seedPeople.where((p) =>
            _likedPeople.contains(p.tmdbId) && !freshIds.contains(p.tmdbId));
        _seedPeople = [...fresh, ...pinned];
        for (final p in _seedPeople) {
          _personById[p.tmdbId] = p;
        }
      }
      _personSeedPage = page;
      _personSeedsMore = res.seedPeople.length >= 20;
      _personSeedsLoading = false;
    });
  }

  List<SushiTastePerson> _peopleForQuery() {
    final q = _personQuery.trim().toLowerCase();
    if (q.isEmpty) {
      return [
        ..._seedPeople,
        ..._personHits
            .where((h) => !_seedPeople.any((s) => s.tmdbId == h.tmdbId)),
      ];
    }
    final matchedSeeds =
        _seedPeople.where((p) => p.name.toLowerCase().contains(q));
    final out = <SushiTastePerson>[..._personHits];
    final seen = {for (final h in _personHits) h.tmdbId};
    for (final p in matchedSeeds) {
      if (seen.add(p.tmdbId)) out.add(p);
    }
    return out;
  }

  Widget _peopleStep(bool dPad) {
    final searching = _personQuery.trim().isNotEmpty;
    final people = _peopleForQuery();
    final cols = AdaptiveLayout.viewSizeOf(context) == ViewSize.phone ? 3 : 5;
    return Column(
      children: [
        _searchField(
          controller: _personSearchCtrl,
          hint: _fa ? 'جستجوی بازیگر…' : 'Search actors…',
          ltr: true,
          onChanged: (q) {
            setState(() => _personQuery = q);
            _personDebounce?.cancel();
            _personDebounce = Timer(const Duration(milliseconds: 450),
                () => unawaited(_runPersonSearch(q)));
          },
        ),
        if (_personSearchLoading || _personSeedsLoading) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(
              color: _salmon, minHeight: 2, backgroundColor: Colors.white12),
        ],
        const SizedBox(height: 12),
        Expanded(
          child: _besideList(
            people.isEmpty && (_personSeedsLoading || _personSearchLoading)
                ? const Center(child: CircularProgressIndicator(color: _salmon))
                : people.isEmpty
                    ? Center(
                        child: Text(
                          searching
                              ? (_fa ? 'چیزی پیدا نشد.' : 'No matches.')
                              : (_fa
                                  ? 'لیست بازیگر خالی است.'
                                  : 'No actors yet.'),
                          style: const TextStyle(color: Colors.white70),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : NotificationListener<ScrollNotification>(
                        onNotification: (n) {
                          if (!searching &&
                              _personSeedsMore &&
                              !_personSeedsLoading &&
                              n.metrics.pixels >=
                                  n.metrics.maxScrollExtent - 280) {
                            unawaited(_refreshPersonSeeds(append: true));
                          }
                          return false;
                        },
                        child: GridView.builder(
                          primary: false,
                          itemCount: people.length +
                              (_personSeedsLoading &&
                                      _personSeedsMore &&
                                      !searching
                                  ? 1
                                  : 0),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: cols,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: 0.72,
                          ),
                          itemBuilder: (context, i) {
                            if (i >= people.length) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(12),
                                  child: CircularProgressIndicator(
                                      color: _salmon, strokeWidth: 2),
                                ),
                              );
                            }
                            final p = people[i];
                            final selected = _likedPeople.contains(p.tmdbId);
                            final url = p.poster.isEmpty
                                ? null
                                : sushiPosterUrl(p.poster, size: 'w185');
                            return _SelectCard(
                              autoFocus: dPad && i == 0,
                              selected: selected,
                              accent: _salmon,
                              onTap: () => setState(() {
                                if (selected) {
                                  _likedPeople.remove(p.tmdbId);
                                } else {
                                  _likedPeople.add(p.tmdbId);
                                  _personById[p.tmdbId] = p;
                                  _pinPersonToSeeds(p);
                                }
                              }),
                              child: Column(
                                children: [
                                  Expanded(
                                    child: ClipOval(
                                      child: AspectRatio(
                                        aspectRatio: 1,
                                        child: url == null
                                            ? ColoredBox(
                                                color: Colors.white12,
                                                child: Center(
                                                    child: Text(p.name.isEmpty
                                                        ? '?'
                                                        : p.name[0])),
                                              )
                                            : CachedNetworkImage(
                                                imageUrl: url,
                                                fit: BoxFit.cover),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  _ltrText(
                                    p.name,
                                    maxLines: 2,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 12),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ),
      ],
    );
  }

  Future<void> _runPersonSearch(String q) async {
    final trimmed = q.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _personHits = const [];
        _personSearchLoading = false;
      });
      return;
    }
    setState(() => _personSearchLoading = true);
    final res = await sushiSearchTastePeople(trimmed);
    if (!mounted) return;
    if (_personQuery.trim() != trimmed) {
      setState(() => _personSearchLoading = false);
      return;
    }
    setState(() {
      _personHits = res?.personHits ?? const [];
      _personSearchLoading = false;
    });
  }

  Widget _qualityStep(bool dPad) {
    // Wire values stay max_height; primary label is human, sub is the tech hint.
    final opts = <({int height, String label, String sub})>[
      (height: 2160, label: _fa ? 'بهترین کیفیت' : 'Best quality', sub: '4K'),
      (
        height: 1080,
        label: _fa ? 'کیفیت بالا' : 'High quality',
        sub: 'HD · 1080p'
      ),
      (height: 720, label: _fa ? 'متوسط' : 'Medium', sub: '720p'),
      (
        height: 480,
        label: _fa ? 'سبک / کم‌حجم' : 'Light / data-saver',
        sub: 'SD · 480p'
      ),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < opts.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          SizedBox(
            height: 78,
            child: _SelectCard(
              autoFocus: dPad && i == 0,
              selected: _maxHeight == opts[i].height,
              accent: _salmon,
              onTap: () => setState(() => _maxHeight = opts[i].height),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    opts[i].label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    opts[i].sub,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _maxHeight == opts[i].height
                          ? _salmon.withValues(alpha: 0.95)
                          : Colors.white54,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _audioStep(bool dPad) {
    final opts = [
      (
        value: 'original',
        icon: IconsaxPlusLinear.headphone,
        label: _fa ? 'صدای اصلی' : 'Original'
      ),
      (
        value: 'dub',
        icon: IconsaxPlusLinear.microphone,
        label: _fa ? 'دوبله' : 'Dubbed'
      ),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < opts.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          SizedBox(
            height: 88,
            child: _SelectCard(
              autoFocus: dPad && i == 0,
              selected: _audio == opts[i].value,
              accent: _salmon,
              onTap: () => setState(() => _audio = opts[i].value),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    opts[i].icon,
                    size: 32,
                    color: _audio == opts[i].value ? _salmon : Colors.white70,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    opts[i].label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 17,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _subsStep(bool dPad) {
    final opts = [
      (
        value: 'on',
        icon: Icons.closed_caption_outlined,
        label: _fa ? 'با زیرنویس' : 'With subtitles'
      ),
      (
        value: 'off',
        icon: Icons.closed_caption_off_outlined,
        label: _fa ? 'بدون زیرنویس' : 'Without subtitles'
      ),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < opts.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          SizedBox(
            height: 88,
            child: _SelectCard(
              autoFocus: dPad && i == 0,
              selected: _subs == opts[i].value,
              accent: _salmon,
              onTap: () => setState(() => _subs = opts[i].value),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    opts[i].icon,
                    size: 32,
                    color: _subs == opts[i].value ? _salmon : Colors.white70,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    opts[i].label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 17,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _subtitleStep(bool dPad) {
    final locales = _orderedSubtitleLocales()
        .where((loc) => localeMatchesQuery(loc, _subtitleQuery))
        .toList();
    final searching = _subtitleQuery.trim().isNotEmpty;
    return Column(
      children: [
        _searchField(
          controller: _subtitleSearchCtrl,
          hint: _fa ? 'جستجوی زبان…' : 'Search language…',
          onChanged: (q) => setState(() => _subtitleQuery = q),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _besideList(
            locales.isEmpty
                ? Center(
                    child: Text(
                      _fa ? 'چیزی پیدا نشد.' : 'No matches.',
                      style: const TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.separated(
                    primary: false,
                    itemCount: locales.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final loc = locales[i];
                      final code = loc.languageCode;
                      final selected = _subtitleLang == code;
                      return FocusButton(
                        autoFocus: dPad && i == 0 && !searching,
                        onTap: () => setState(() => _subtitleLang = code),
                        borderRadius: FladderTheme.defaultShape.borderRadius,
                        child: Material(
                          color: selected
                              ? _salmon.withValues(alpha: 0.25)
                              : Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHigh
                                  .withValues(alpha: 0.85),
                          shape: FladderTheme.defaultShape,
                          child: InkWell(
                            onTap: () => setState(() => _subtitleLang = code),
                            customBorder: FladderTheme.defaultShape,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 18, vertical: 16),
                              child: Localizations.override(
                                context: context,
                                locale: loc,
                                child: Builder(
                                  builder: (context) {
                                    var name = code.toUpperCase();
                                    try {
                                      name = context.localized.nativeName;
                                    } catch (_) {}
                                    return Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            name,
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                        if (selected)
                                          const Icon(Icons.check,
                                              color: _salmon),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  /// Saved subtitle lang first, then app language, Persian, English.
  /// A tap in this visit does not move that row.
  List<Locale> _orderedSubtitleLocales() {
    final all = List<Locale>.from(AppLocalizations.supportedLocales);
    final appCode = Localizations.localeOf(context).languageCode;
    final selectedCode = _pinnedSubtitleLang;
    Locale? selected;
    Locale? app;
    Locale? fa;
    Locale? en;
    final rest = <Locale>[];
    for (final loc in all) {
      final code = loc.languageCode;
      if (selectedCode.isNotEmpty && code == selectedCode && selected == null) {
        selected = loc;
        continue;
      }
      if (code == appCode && app == null) {
        app = loc;
      } else if (code == 'fa' && fa == null) {
        fa = loc;
      } else if (code == 'en' && en == null) {
        en = loc;
      } else {
        rest.add(loc);
      }
    }
    rest.sort((a, b) => a.toLanguageTag().compareTo(b.toLanguageTag()));
    return [
      if (selected != null) selected,
      if (app != null) app,
      if (fa != null) fa,
      if (en != null) en,
      ...rest,
    ];
  }

  void _pinTitleToSeeds(SushiRow row) {
    final exists =
        _seedTitles.any((s) => s.tmdbId == row.tmdbId && s.kind == row.kind);
    if (exists) return;
    _seedTitles = [..._seedTitles, row];
  }

  void _pinPersonToSeeds(SushiTastePerson person) {
    if (person.tmdbId == 0) return;
    final exists = _seedPeople.any((s) => s.tmdbId == person.tmdbId);
    if (exists) return;
    _seedPeople = [..._seedPeople, person];
  }

  /// English TMDB titles/names stay LTR even when the wizard UI is Persian RTL.
  Widget _ltrText(
    String text, {
    int maxLines = 2,
    TextAlign textAlign = TextAlign.start,
    TextStyle? style,
  }) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        textAlign: textAlign,
        style: style,
      ),
    );
  }

  Widget _searchField({
    required TextEditingController controller,
    required String hint,
    required ValueChanged<String> onChanged,
    bool ltr = false,
  }) {
    final field = SushiDpadTextField(
      controller: controller,
      label: '',
      hint: hint,
      hintStyle: const TextStyle(color: Colors.white54),
      style: const TextStyle(color: Colors.white),
      textInputAction: TextInputAction.search,
      useSystemIme: false,
      fillColor: Colors.white12,
      prefixIcon: const Icon(Icons.search, color: Colors.white54),
      keyboardLayoutLocale: ltr ? const Locale('en') : null,
      onChanged: onChanged,
    );
    if (!ltr) return field;
    return Directionality(textDirection: TextDirection.ltr, child: field);
  }

  Widget _choiceGrid({
    required bool dPad,
    required int crossAxisCount,
    required int itemCount,
    required Widget Function(BuildContext, int) builder,
    double childAspectRatio = 1.1,
  }) {
    return GridView.builder(
      primary: false,
      itemCount: itemCount,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: childAspectRatio,
      ),
      itemBuilder: builder,
    );
  }

  /// Phone keeps Back/Next on the bottom bar. Wider screens use the side rails.
  Widget _footer(bool dPad) {
    final backLabel = _fa ? 'قبلی' : 'Back';
    final nextLabel = _step == _activeSteps.last
        ? (_fa ? 'تمام' : 'Done')
        : (_fa ? 'بعدی' : 'Next');

    return Row(
      children: [
        if (_history.isNotEmpty)
          Expanded(
            child: _FooterBtn(
              autofocus: false,
              label: backLabel,
              outlined: true,
              onTap: _saving ? null : _goBack,
            ),
          ),
        if (_history.isNotEmpty) const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: _FooterBtn(
            autofocus: dPad,
            label: _saving ? '...' : nextLabel,
            filled: true,
            onTap: _saving || _mustChoose ? null : _goNext,
          ),
        ),
      ],
    );
  }

  String get _backLabel => _fa ? 'قبلی' : 'Back';

  String get _nextLabel => _step == _activeSteps.last
      ? (_fa ? 'تمام' : 'Done')
      : (_fa ? 'بعدی' : 'Next');

  /// Scrolling lists already have a bounded height. Rails take that full height.
  Widget _besideList(Widget child) {
    if (!_wideNav) return child;
    return Row(
      textDirection: TextDirection.ltr,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _backRail(),
        const SizedBox(width: 10),
        Expanded(child: child),
        const SizedBox(width: 10),
        _nextRail(),
      ],
    );
  }

  Widget _backRail() {
    if (_history.isEmpty) return const SizedBox(width: _SideRail.width);
    return _SideRail(
      label: _backLabel,
      filled: false,
      onTap: _saving ? null : _goBack,
    );
  }

  Widget _nextRail() {
    final dPad = AdaptiveLayout.inputDeviceOf(context) == InputDevice.dPad;
    return _SideRail(
      label: _saving ? '...' : _nextLabel,
      filled: true,
      autofocus: dPad,
      onTap: _saving || _mustChoose ? null : _goNext,
    );
  }
}

class _SideRail extends StatelessWidget {
  const _SideRail({
    required this.label,
    required this.onTap,
    required this.filled,
    this.autofocus = false,
  });

  static const width = 56.0;
  static const _salmon = Color(0xFFE37A42);

  final String label;
  final VoidCallback? onTap;
  final bool filled;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final letters = RotatedBox(
      quarterTurns: 1,
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontWeight: filled ? FontWeight.w700 : FontWeight.w600,
          fontSize: 16,
        ),
      ),
    );
    final enabled = onTap != null;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: filled || !enabled
          ? BorderSide.none
          : const BorderSide(color: Colors.white38),
    );
    return SizedBox(
      width: width,
      child: Material(
        color: filled
            ? (enabled ? _salmon : _salmon.withValues(alpha: 0.35))
            : Colors.transparent,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          autofocus: autofocus && enabled,
          onTap: onTap,
          customBorder: shape,
          child: Center(child: letters),
        ),
      ),
    );
  }
}

class _SelectCard extends StatelessWidget {
  const _SelectCard({
    required this.selected,
    required this.accent,
    required this.onTap,
    required this.child,
    this.autoFocus = false,
  });

  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  final Widget child;
  final bool autoFocus;

  @override
  Widget build(BuildContext context) {
    return FocusButton(
      autoFocus: autoFocus,
      onTap: onTap,
      borderRadius: FladderTheme.defaultShape.borderRadius,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHigh
              .withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? accent : Colors.white24,
            width: selected ? 2.5 : 1,
          ),
        ),
        child: child,
      ),
    );
  }
}

class _FooterBtn extends StatelessWidget {
  const _FooterBtn({
    required this.label,
    required this.onTap,
    this.filled = false,
    this.outlined = false,
    this.autofocus = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool filled;
  final bool outlined;
  final bool autofocus;

  static const _salmon = Color(0xFFE37A42);

  @override
  Widget build(BuildContext context) {
    final child = filled
        ? FilledButton(
            autofocus: autofocus,
            onPressed: onTap,
            style: FilledButton.styleFrom(
              backgroundColor: _salmon,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: FladderTheme.defaultShape,
            ),
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          )
        : OutlinedButton(
            autofocus: autofocus,
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white38),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: FladderTheme.defaultShape,
            ),
            child: Text(label),
          );
    return child;
  }
}

class _GenreOpt {
  const _GenreOpt(this.id, this.en, this.fa, this.icon);
  final String id;
  final String en;
  final String fa;
  final IconData icon;
}

const _tasteGenres = <_GenreOpt>[
  _GenreOpt('Action', 'Action', 'اکشن', Icons.flash_on_outlined),
  _GenreOpt('Adventure', 'Adventure', 'ماجراجویی', Icons.explore_outlined),
  _GenreOpt('Animation', 'Animation', 'انیمیشن', Icons.brush_outlined),
  _GenreOpt('Comedy', 'Comedy', 'کمدی', Icons.sentiment_satisfied_alt_outlined),
  _GenreOpt('Crime', 'Crime', 'جنایی', Icons.gavel_outlined),
  _GenreOpt('Documentary', 'Documentary', 'مستند', Icons.article_outlined),
  _GenreOpt('Drama', 'Drama', 'درام', Icons.theater_comedy_outlined),
  _GenreOpt('Family', 'Family', 'خانوادگی', Icons.family_restroom_outlined),
  _GenreOpt('Fantasy', 'Fantasy', 'فانتزی', Icons.auto_awesome_outlined),
  _GenreOpt('History', 'History', 'تاریخی', Icons.menu_book_outlined),
  _GenreOpt('Horror', 'Horror', 'ترسناک', Icons.nightlight_outlined),
  _GenreOpt('Music', 'Music', 'موسیقی', Icons.music_note_outlined),
  _GenreOpt('Mystery', 'Mystery', 'معمایی', Icons.search_outlined),
  _GenreOpt('Romance', 'Romance', 'عاشقانه', Icons.favorite_outline),
  _GenreOpt('Science Fiction', 'Sci-Fi', 'علمی‌تخیلی', Icons.memory_outlined),
  _GenreOpt('Thriller', 'Thriller', 'هیجانی', Icons.bolt_outlined),
  _GenreOpt('War', 'War', 'جنگی', Icons.military_tech_outlined),
  _GenreOpt('Western', 'Western', 'وسترن', Icons.landscape_outlined),
];

String sushiPosterUrl(String stem, {String size = 'w500'}) {
  if (stem.isEmpty) return '';
  if (stem.startsWith('http')) return stem;
  return 'https://image.tmdb.org/t/p/$size/$stem.jpg';
}
