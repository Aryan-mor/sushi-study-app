import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/theme.dart';

/// First login screen: pick Telegram-account (phone) vs personal-bot.
///
/// Phone: stacked. Tablet+: start/end pair (phone at start — left in EN, right in FA).
class SushiLoginMethodChooser extends StatelessWidget {
  const SushiLoginMethodChooser({
    required this.sideBySide,
    required this.onPhone,
    required this.onBot,
    super.key,
  });

  final bool sideBySide;
  final VoidCallback onPhone;
  final VoidCallback onBot;

  static const _salmon = Color(0xFFE37A42);

  @override
  Widget build(BuildContext context) {
    final fa = Localizations.localeOf(context).languageCode == 'fa';
    final theme = Theme.of(context);
    final accent = _salmon;

    final phoneCard = _MethodCard(
      key: const Key('login-method-phone'),
      expand: sideBySide,
      autofocus: true,
      accent: accent,
      filled: true,
      icon: IconsaxPlusLinear.call,
      badge: fa ? 'آسان‌تر' : 'Easiest',
      title: fa ? 'ورود آسان با شماره موبایل' : 'Easy sign-in with your phone',
      body: fa
          ? 'با اکانت تلگرامت وارد شو — همون شماره‌ای که تلگرام داری.'
          : 'Sign in with your Telegram account — the number you already use.',
      action: fa ? 'ادامه با شماره' : 'Continue with phone',
      onSelect: onPhone,
    );

    final botCard = _MethodCard(
      key: const Key('login-method-bot'),
      expand: sideBySide,
      accent: accent,
      filled: false,
      icon: IconsaxPlusLinear.cpu,
      title: fa ? 'ورود با ربات، بدون شماره' : 'Sign in with your own bot',
      body: fa
          ? 'بدون لاگین شماره موبایل. سوشی به اکانت تلگرامت وصل نمی‌شه.'
          : 'No phone number. Sushi never logs into your Telegram account.',
      hint: fa
          ? 'فقط بار اول دو مرحله‌ست. بعدش با یک ضربه وارد می‌شی.'
          : 'First time takes two steps. After that, one tap.',
      action: fa ? 'ادامه با ربات' : 'Continue with bot',
      onSelect: onBot,
    );

    final split = sideBySide
        ? IntrinsicHeight(
            child: Row(
              key: const Key('login-method-split'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: phoneCard),
                const SizedBox(width: 16),
                Expanded(child: botCard),
              ],
            ),
          )
        : Column(
            key: const Key('login-method-split'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              phoneCard,
              const SizedBox(height: 16),
              botCard,
            ],
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          fa ? 'چطور می‌خوای وارد بشی؟' : 'How do you want to sign in?',
          style: theme.textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          fa
              ? 'شماره موبایل سریع‌تره. ربات برای وقتی‌ست که نمی‌خوای اکانت تلگرام وصل بشه.'
              : 'Phone is the quick path. The bot is for when you don’t want to link Telegram.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        split,
      ],
    );
  }
}

class _MethodCard extends StatelessWidget {
  const _MethodCard({
    required this.expand,
    required this.accent,
    required this.filled,
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
    required this.onSelect,
    this.badge,
    this.hint,
    this.autofocus = false,
    super.key,
  });

  final bool expand;
  final Color accent;
  final bool filled;
  final IconData icon;
  final String? badge;
  final String title;
  final String body;
  final String? hint;
  final String action;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // Both variants get an explicit, high-contrast focus ring — the bot card's plain
    // OutlinedButton was otherwise nearly invisible when focused by keyboard / D-pad.
    final restingSide =
        filled ? BorderSide.none : BorderSide(color: accent.withValues(alpha: 0.7));
    final focusSide =
        BorderSide(color: filled ? Colors.white : accent, width: 3);
    final buttonStyle = (filled
            ? FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                disabledBackgroundColor: accent.withValues(alpha: 0.4),
                minimumSize: const Size.fromHeight(48),
                shape: FladderTheme.defaultShape,
              )
            : OutlinedButton.styleFrom(
                foregroundColor: accent,
                side: restingSide,
                minimumSize: const Size.fromHeight(48),
                shape: FladderTheme.defaultShape,
              ))
        .copyWith(
      side: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.focused) ? focusSide : restingSide,
      ),
      elevation: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.focused) ? 6.0 : 0.0,
      ),
    );

    return Material(
      color: scheme.surfaceContainerHigh,
      shape: FladderTheme.defaultShape.copyWith(
        side: BorderSide(
          color: filled ? accent.withValues(alpha: 0.45) : scheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        canRequestFocus: false,
        onTap: onSelect,
        customBorder: FladderTheme.defaultShape,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: accent, size: 24),
                  ),
                  if (badge != null) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        badge!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                body,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              if (hint != null) ...[
                const SizedBox(height: 10),
                Text(
                  hint!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
              if (expand) const Spacer() else const SizedBox(height: 20),
              filled
                  ? FilledButton(
                      autofocus: autofocus,
                      style: buttonStyle,
                      onPressed: onSelect,
                      child: Text(action),
                    )
                  : OutlinedButton(
                      autofocus: autofocus,
                      style: buttonStyle,
                      onPressed: onSelect,
                      child: Text(action),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
