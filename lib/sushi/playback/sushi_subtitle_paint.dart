/// Where the current cue is painted.
///
/// ASS/SSA + libass: mpv burns into the video. Overlay must shrink or a
/// second copy appears. SRT/VTT: `_configureMpvForTextSubtitle` hides mpv
/// OSD (`sub-visibility=no`); Flutter overlay is the only paint path.
///
/// Desktop used to shrink overlay for *every* codec (`libass_desktop_burn`).
/// That deadlocked automatic SRT: mpv OSD off, Flutter also off, nothing shown.
String sushiSubtitlePaintPath({
  required bool libassEnabled,
  required bool isAss,
  required bool textEmpty,
}) {
  if (libassEnabled && isAss) return 'libass_ass_burn';
  if (textEmpty) return 'empty';
  return 'flutter_overlay';
}

bool sushiSubtitlePaintsFlutterOverlay(String path) => path == 'flutter_overlay';
