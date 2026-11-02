import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/focus_provider.dart';
import 'package:fladder/widgets/keyboard/slide_in_keyboard.dart';

/// TV-friendly text field with a thick focus ring.
///
/// [useSystemIme]: when true (default), Select/OK opens the Android TV system keyboard.
/// When false, uses Fladder's slide-in mini keyboard.
///
/// Phone/tablet: single [FocusNode] on the [TextField] so Android opens the correct
/// IME for [keyboardType]. TV keeps a wrapper focus ring + separate EditableText node.
class SushiDpadTextField extends StatefulWidget {
  const SushiDpadTextField({
    required this.controller,
    required this.label,
    this.focusNode,
    this.hint,
    this.keyboardType,
    this.textInputAction = TextInputAction.done,
    this.inputFormatters,
    this.style,
    this.textAlign = TextAlign.start,
    this.autofocus = false,
    this.obscureText = false,
    this.autofillHints,
    this.useSystemIme = true,
    this.enabled = true,
    this.onChanged,
    this.onKeyboardClosed,
    this.onMoveFocusDown,
    this.prefixIcon,
    this.fillColor,
    this.hintStyle,
    this.keyboardLayoutLocale,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String label;
  final String? hint;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final TextStyle? style;
  final TextAlign textAlign;
  final bool autofocus;
  final bool obscureText;
  final Iterable<String>? autofillHints;

  /// Prefer Android system IME over Fladder mini keyboard (TV login default).
  final bool useSystemIme;

  /// When false (e.g. auth submit in flight), field + OK are inert.
  final bool enabled;

  final ValueChanged<String>? onChanged;

  /// Called after keyboard closes (custom KB) or after Done on system IME.
  final VoidCallback? onKeyboardClosed;

  /// D-pad Down while field focused and IME closed (e.g. move to Confirm).
  final VoidCallback? onMoveFocusDown;

  final Widget? prefixIcon;
  final Color? fillColor;
  final TextStyle? hintStyle;

  /// TV mini-keyboard script. Null follows the app language.
  final Locale? keyboardLayoutLocale;

  @override
  State<SushiDpadTextField> createState() => SushiDpadTextFieldState();
}

class SushiDpadTextFieldState extends State<SushiDpadTextField> {
  late final FocusNode _externalOrOwned = widget.focusNode ?? FocusNode();

  /// TV-only: EditableText node under the wrapper ring.
  final FocusNode _tvTextFocus = FocusNode();
  bool _hasFocus = false;
  bool _ownsFocus = false;

  bool get _isDpad => AdaptiveLayout.inputDeviceOf(context) == InputDevice.dPad;

  bool get _useCustomKb => _isDpad && !widget.useSystemIme;

  /// Node that owns the [TextField] on the current device.
  FocusNode get _fieldFocus => _isDpad ? _tvTextFocus : _externalOrOwned;

  @override
  void initState() {
    super.initState();
    _ownsFocus = widget.focusNode == null;
    _externalOrOwned.addListener(_onFocusChange);
    _tvTextFocus.addListener(_onFocusChange);
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) requestFocus();
      });
    }
  }

  void _onFocusChange() {
    if (!mounted) return;
    setState(() {
      _hasFocus = _externalOrOwned.hasFocus || _tvTextFocus.hasFocus;
    });
  }

  /// Phone: focus EditableText (correct [keyboardType] IME).
  /// TV: focus wrapper ring; Select opens IME.
  void requestFocus() {
    _externalOrOwned.requestFocus();
  }

  /// Focus + open system IME after the field is attached (phone login step changes).
  void requestFocusAndShowIme() {
    if (_isDpad) {
      requestFocus();
      return;
    }
    // Two frames: first attach EditableText connection (keyboardType), then show IME.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.enabled) return;
      _externalOrOwned.requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !widget.enabled) return;
        if (!_externalOrOwned.hasFocus) {
          _externalOrOwned.requestFocus();
        }
        if (_externalOrOwned.hasFocus) {
          SystemChannels.textInput.invokeMethod<void>('TextInput.show');
        }
      });
    });
  }

  @override
  void dispose() {
    _externalOrOwned.removeListener(_onFocusChange);
    _tvTextFocus.removeListener(_onFocusChange);
    if (_ownsFocus) _externalOrOwned.dispose();
    _tvTextFocus.dispose();
    super.dispose();
  }

  void _showSystemIme() {
    _tvTextFocus.requestFocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.show');
  }

  Future<void> _openCustomKeyboard() async {
    await openKeyboard(
      context,
      widget.controller,
      inputType: widget.keyboardType,
      inputAction: widget.textInputAction,
      layoutLocale: widget.keyboardLayoutLocale,
      onChanged: () {
        widget.onChanged?.call(widget.controller.text);
        if (mounted) setState(() {});
      },
    );
    if (!mounted) return;
    widget.onKeyboardClosed?.call();
    _externalOrOwned.requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (!_isDpad || !widget.enabled) return KeyEventResult.ignored;

    // System IME open: never steal arrows / Select from the on-screen keyboard.
    if (!_useCustomKb && MediaQuery.viewInsetsOf(context).bottom > 0) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
        widget.onMoveFocusDown != null) {
      if (_tvTextFocus.hasFocus) {
        _tvTextFocus.unfocus();
        SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      }
      widget.onMoveFocusDown!();
      return KeyEventResult.handled;
    }

    if (acceptKeys.contains(event.logicalKey)) {
      if (_useCustomKb) {
        unawaited(_openCustomKeyboard());
      } else {
        _showSystemIme();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fill =
        theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35);
    final enabled = widget.enabled;
    final radius = BorderRadius.circular(12);
    // Phone: InputDecorator focusedBorder + label notch. TV: wrapper ring only while
    // waiting for Select (TextField itself not focused yet).
    final showDpadRing = _isDpad &&
        enabled &&
        _externalOrOwned.hasFocus &&
        !_tvTextFocus.hasFocus;
    final labelColor = (_hasFocus && enabled)
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    final searchChrome = widget.prefixIcon != null || widget.fillColor != null;
    final textField = TextField(
      controller: widget.controller,
      focusNode: _fieldFocus,
      enabled: enabled,
      readOnly: _useCustomKb || !enabled,
      showCursor: enabled && !_useCustomKb,
      obscureText: widget.obscureText,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      inputFormatters: widget.inputFormatters,
      style: widget.style,
      textAlign: widget.textAlign,
      autofillHints: widget.autofillHints,
      enableSuggestions: false,
      autocorrect: false,
      canRequestFocus: enabled && !_useCustomKb,
      onTap: enabled && _isDpad
          ? () {
              if (_useCustomKb) {
                unawaited(_openCustomKeyboard());
              } else {
                _showSystemIme();
              }
            }
          : null,
      onChanged: enabled ? widget.onChanged : null,
      onSubmitted: enabled
          ? (_) {
              widget.onKeyboardClosed?.call();
            }
          : null,
      decoration: InputDecoration(
        labelText: widget.label.isEmpty ? null : widget.label,
        hintText: widget.hint,
        hintStyle: widget.hintStyle,
        prefixIcon: widget.prefixIcon,
        filled: true,
        fillColor: widget.fillColor ?? fill,
        labelStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        floatingLabelStyle:
            TextStyle(color: labelColor, fontWeight: FontWeight.w600),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: radius,
          borderSide: searchChrome ? BorderSide.none : const BorderSide(),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: searchChrome
              ? BorderSide.none
              : BorderSide(
                  color: theme.colorScheme.outline.withValues(alpha: 0.45)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(
            color:
                searchChrome ? Colors.transparent : theme.colorScheme.primary,
            width: searchChrome ? 0 : 2,
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide.none,
        ),
      ),
    );

    final ring = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      clipBehavior: Clip.none,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(
          width: showDpadRing ? 3 : (_isDpad ? 2 : 0),
          color: showDpadRing ? theme.colorScheme.primary : Colors.transparent,
        ),
      ),
      child: _isDpad
          ? Focus(
              focusNode: _externalOrOwned,
              canRequestFocus: enabled,
              onKeyEvent: _onKey,
              child: ExcludeFocusTraversal(child: textField),
            )
          : textField,
    );

    final field = Opacity(
      opacity: enabled ? 1 : 0.55,
      child: ring,
    );
    if (!_isDpad || widget.useSystemIme) return field;
    return BackButtonListener(
      onBackButtonPressed: () {
        if (isKeyboardOpen.value) return Future.value(false);
        if (!_externalOrOwned.hasFocus && !_tvTextFocus.hasFocus) {
          return Future.value(false);
        }
        _tvTextFocus.unfocus();
        SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
        _externalOrOwned.unfocus();
        return Future.value(true);
      },
      child: field,
    );
  }
}
