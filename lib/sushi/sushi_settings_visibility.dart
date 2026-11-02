/// Which Fladder settings entries are shown in Sushi / Sushi builds.
abstract final class SushiSettingsVisibility {
  static bool get isSushiMode => true;

  static bool get showControlPanel => !isSushiMode;

  static bool get showSwitchUser => true;

  static bool get showProfilePasswordReset => !isSushiMode;

  static bool get showProfileSubtitlePreferences => !isSushiMode;

  static bool get showProfileJellyfinNotifications => !isSushiMode;

  static bool get showProfileLocalUrl => !isSushiMode;

  /// Full library order editor (reorder + latest excludes + hide played).
  static bool get showProfileLibraryOrder => true;

  /// Grouped libraries checkboxes (persisted via UserConfiguration on the server).
  static bool get showProfileGroupedFolders => !isSushiMode;

  static bool get showProfileHomePreferencesSave =>
      showProfileLibraryOrder || (isSushiMode && showProfileGroupedFolders);

  /// Layout sizes, layout modes, system IME (Sushi client settings).
  static bool get showClientSettingsAdvanced => !isSushiMode;
}
