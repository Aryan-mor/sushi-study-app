import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/l10n/generated/app_localizations.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/sushi/sushi_dpad_text_field.dart';
import 'package:fladder/sushi/sushi_pending_route.dart';
import 'package:fladder/sushi/sushi_splash_brand.dart';
import 'package:fladder/theme.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/focus_provider.dart';
import 'package:fladder/util/localization_helper.dart';

/// First-launch language gate. English → Persian → remaining [AppLocalizations.supportedLocales].
@RoutePage()
class SushiLanguageScreen extends ConsumerStatefulWidget {
  const SushiLanguageScreen({
    this.thenLoggedIn = false,
    super.key,
  });

  /// After pick: continue as if splash finished with this auth state.
  final bool thenLoggedIn;

  static const _salmon = Color(0xFFE37A42);

  static List<Locale> orderedLocales() {
    final all = List<Locale>.from(AppLocalizations.supportedLocales);
    Locale? en;
    Locale? fa;
    final rest = <Locale>[];
    for (final loc in all) {
      if (loc.languageCode == 'en' && en == null) {
        en = loc;
      } else if (loc.languageCode == 'fa' && fa == null) {
        fa = loc;
      } else {
        rest.add(loc);
      }
    }
    rest.sort((a, b) => a.toLanguageTag().compareTo(b.toLanguageTag()));
    return [
      if (en != null) en,
      if (fa != null) fa,
      ...rest,
    ];
  }

  @override
  ConsumerState<SushiLanguageScreen> createState() =>
      _SushiLanguageScreenState();
}

class _SushiLanguageScreenState extends ConsumerState<SushiLanguageScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _pick(Locale locale) async {
    ref.read(clientSettingsProvider.notifier).update(
          (state) => state.copyWith(selectedLocale: locale),
        );
    if (!context.mounted) return;
    if (widget.thenLoggedIn) {
      sushiFlushBufferedPendingPath(ref);
      await sushiNavigateAfterLogin(context, ref);
      return;
    }
    sushiFlushBufferedPendingPath(ref);
    await context.router.replace(const SushiLoginRoute());
    ref.read(authProvider.notifier).initModel();
  }

  @override
  Widget build(BuildContext context) {
    final searching = _query.trim().isNotEmpty;
    final locales = SushiLanguageScreen.orderedLocales()
        .where((loc) => localeMatchesQuery(loc, _query))
        .toList();
    final dPad = AdaptiveLayout.inputDeviceOf(context) == InputDevice.dPad;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: SushiSplashBrand.splashBackground,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Choose your language',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'زبان خود را انتخاب کنید',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white70,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  SushiDpadTextField(
                    controller: _searchCtrl,
                    label: '',
                    hint: 'Search language / جستجوی زبان',
                    hintStyle: const TextStyle(color: Colors.white54),
                    style: const TextStyle(color: Colors.white),
                    textInputAction: TextInputAction.search,
                    useSystemIme: false,
                    fillColor: Colors.white12,
                    prefixIcon: const Icon(Icons.search, color: Colors.white54),
                    onChanged: (q) => setState(() => _query = q),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: locales.isEmpty
                        ? const Center(
                            child: Text(
                              'No matches / چیزی پیدا نشد',
                              style: TextStyle(color: Colors.white70),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.separated(
                            itemCount: locales.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final locale = locales[index];
                              return _LanguageTile(
                                locale: locale,
                                autoFocus: dPad && index == 0 && !searching,
                                accent: SushiLanguageScreen._salmon,
                                onTap: () => _pick(locale),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.locale,
    required this.onTap,
    required this.accent,
    this.autoFocus = false,
  });

  final Locale locale;
  final VoidCallback onTap;
  final Color accent;
  final bool autoFocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FocusButton(
      autoFocus: autoFocus,
      onTap: onTap,
      borderRadius: FladderTheme.defaultShape.borderRadius,
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.85),
        shape: FladderTheme.defaultShape,
        child: InkWell(
          onTap: onTap,
          customBorder: FladderTheme.defaultShape,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Localizations.override(
              context: context,
              locale: locale,
              child: Builder(
                builder: (context) {
                  var name = locale.languageCode.toUpperCase();
                  try {
                    name = context.localized.nativeName;
                  } catch (_) {}
                  return Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        locale.toDisplayCode(),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: accent,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
