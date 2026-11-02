import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/video_player_helper.g.dart',
    dartOptions: DartOptions(),
    kotlinOut: 'android/app/src/main/kotlin/app/sushi/api/VideoPlayerHelper.g.kt',
    kotlinOptions: KotlinOptions(),
    dartPackageName: 'nl_jknaapen_fladder.video',
  ),
)
class SimpleItemModel {
  final String id;
  final String title;
  final String? subTitle;
  final String? overview;
  final String? logoUrl;
  final String primaryPoster;

  const SimpleItemModel({
    required this.id,
    required this.title,
    this.subTitle,
    this.overview,
    this.logoUrl,
    required this.primaryPoster,
  });
}

enum PlaybackType {
  direct,
  transcoded,
  offline,
  tv,
}

class MediaInfo {
  final PlaybackType playbackType;
  final String videoInformation;

  const MediaInfo({
    required this.playbackType,
    required this.videoInformation,
  });
}

class PlayableData {
  final SimpleItemModel currentItem;
  final String description;
  final int startPosition;
  final int defaultAudioTrack;
  final List<AudioTrack> audioTracks;
  final int defaultSubtrack;
  final List<SubtitleTrack> subtitleTracks;
  final TrickPlayModel? trickPlayModel;
  final List<Chapter> chapters;
  final List<MediaSegment> segments;
  final SimpleItemModel? previousVideo;
  final SimpleItemModel? nextVideo;
  final MediaInfo mediaInfo;
  final String url;

  /// False for a personal video (ADR 0037): the subtitle picker lists only the file's own tracks,
  /// with no Automatic, Online or AI rows.
  final bool sushiSubtitleTools;

  PlayableData({
    required this.currentItem,
    required this.description,
    required this.startPosition,
    required this.defaultAudioTrack,
    this.audioTracks = const [],
    required this.defaultSubtrack,
    this.subtitleTracks = const [],
    this.trickPlayModel,
    this.chapters = const [],
    this.segments = const [],
    this.previousVideo,
    this.nextVideo,
    required this.mediaInfo,
    required this.url,
    this.sushiSubtitleTools = true,
  });
}

enum MediaSegmentType {
  commercial,
  preview,
  recap,
  intro,
  outro,
}

class MediaSegment {
  final MediaSegmentType type;
  final String name;
  final int start;
  final int end;

  const MediaSegment({
    required this.type,
    required this.name,
    required this.start,
    required this.end,
  });
}

class AudioTrack {
  final String name;
  final String languageCode;
  final String codec;
  final int index;
  final bool external;
  final String? url;

  const AudioTrack({
    required this.name,
    required this.languageCode,
    required this.codec,
    required this.index,
    required this.external,
    required this.url,
  });
}

class SubtitleTrack {
  final String name;
  final String languageCode;
  final String codec;
  final int index;
  final bool external;
  final String? url;

  const SubtitleTrack({
    required this.name,
    required this.languageCode,
    required this.codec,
    required this.index,
    required this.external,
    required this.url,
  });
}

/// Muxed audio row reported by the native (Exo) player for client-side merge + verified manifest.
class NativeMuxedAudioRow {
  final String trackId;
  final String title;
  final String languageCode;
  final String codec;

  const NativeMuxedAudioRow({
    required this.trackId,
    required this.title,
    required this.languageCode,
    required this.codec,
  });
}

/// Muxed subtitle row reported by the native (Exo) player for client-side merge + verified manifest.
class NativeMuxedSubtitleRow {
  final String trackId;
  final String title;
  final String languageCode;
  final String codec;

  const NativeMuxedSubtitleRow({
    required this.trackId,
    required this.title,
    required this.languageCode,
    required this.codec,
  });
}

class Chapter {
  final String name;
  final String url;
  // Duration in milliseconds
  final int time;

  const Chapter({
    required this.name,
    required this.url,
    required this.time,
  });
}

class TrickPlayModel {
  final int width;
  final int height;
  final int tileWidth;
  final int tileHeight;
  final int thumbnailCount;
  //Duration in milliseconds
  final int interval;
  final List<String> images;

  const TrickPlayModel({
    required this.width,
    required this.height,
    required this.tileWidth,
    required this.tileHeight,
    required this.thumbnailCount,
    required this.interval,
    this.images = const [],
  });
}

class StartResult {
  String? resultValue;
}

@HostApi()
abstract class NativeVideoActivity {
  @async
  StartResult launchActivity();
  void disposeActivity();

  bool isLeanBackEnabled();
}

@HostApi()
abstract class VideoPlayerApi {
  @async
  bool sendPlayableModel(PlayableData playableData);

  @async
  bool sendTVGuideModel(TVGuideModel guide);

  @async
  bool open(String url, bool play);

  void setLooping(bool looping);

  /// Sets the volume, with 0.0 being muted and 1.0 being full volume.
  void setVolume(double volume);

  /// Sets the playback speed as a multiple of normal speed.
  void setPlaybackSpeed(double speed);

  void play();

  /// Pauses playback if the video is currently playing.
  void pause();

  /// Seeks to the given playback position, in milliseconds.
  void seekTo(int position);

  void stop();

  void setSubtitleSettings(SubtitleSettings settings);

  /// Re-applies default audio/subtitle selection from the last [sendPlayableModel] (e.g. after Flutter merges muxed streams).
  @async
  bool refreshDefaultTrackSelection();

  /// Sideload a decoded `.srt` as an ExoPlayer text track without tearing down Telegram playback.
  @async
  bool setSubtitleFromText(String data, String? title, String? languageCode);

  @async
  bool clearExternalSubtitle();

  /// After a text sniff says the muxed track is Persian, rewrite the picker label.
  void setEmbeddedSubtitleLanguage(int index, String languageCode);
}

class PlaybackState {
  //Milliseconds
  final int position;
  //Milliseconds
  final int buffered;
  //Milliseconds
  final int duration;
  final bool playing;
  final bool buffering;
  final bool completed;
  final bool failed;

  const PlaybackState({
    required this.position,
    required this.buffered,
    required this.duration,
    required this.playing,
    required this.buffering,
    required this.completed,
    required this.failed,
  });
}

class SubtitleSettings {
  final double fontSize;
  final int fontWeight;
  final double verticalOffset;
  final int color;
  final int outlineColor;
  final double outlineSize;
  final int backgroundColor;
  final double shadow;

  const SubtitleSettings({
    required this.fontSize,
    required this.fontWeight,
    required this.verticalOffset,
    required this.color,
    required this.outlineColor,
    required this.outlineSize,
    required this.backgroundColor,
    required this.shadow,
  });
}

class TVGuideModel {
  final List<GuideChannel> channels;
  final int startMs;
  final int endMs;
  final GuideProgram? currentProgram;

  const TVGuideModel({
    this.channels = const [],
    required this.startMs,
    required this.endMs,
    required this.currentProgram,
  });
}

class GuideChannel {
  final String channelId;
  final String name;
  final String? logoUrl;
  final List<GuideProgram> programs;
  final bool programsLoaded;

  const GuideChannel({
    required this.channelId,
    required this.name,
    this.logoUrl,
    this.programs = const [],
    required this.programsLoaded,
  });
}

class GuideProgram {
  final String id;
  final String channelId;
  final String name;
  final int startMs;
  final int endMs;
  final String? primaryPoster;
  final String? overview;
  final String? subTitle;

  const GuideProgram({
    required this.id,
    required this.channelId,
    required this.name,
    required this.startMs,
    required this.endMs,
    this.primaryPoster,
    this.overview,
    this.subTitle,
  });
}

/// One sub-plus pack row for the native TV online-subtitle sheet.
class SushiOnlineSubtitlePack {
  final String tag;
  final String title;
  final String hint;

  const SushiOnlineSubtitlePack({
    required this.tag,
    required this.title,
    required this.hint,
  });
}

/// Result of auto-load / download / translate. [errorCode] is `missing_key`,
/// `no_source`, `no_results`, `need_pick`, or `failed`.
class SushiSubtitleActionResult {
  final bool ok;
  final String? errorCode;
  final String? label;
  final List<String>? fileNames;
  final String? tag;

  const SushiSubtitleActionResult({
    required this.ok,
    this.errorCode,
    this.label,
    this.fileNames,
    this.tag,
  });
}

class SushiAiKeySetup {
  final String deepLink;
  final bool telegramInstalled;

  const SushiAiKeySetup({
    required this.deepLink,
    required this.telegramInstalled,
  });
}

@FlutterApi()
abstract class VideoPlayerListenerCallback {
  void onPlaybackStateChanged(PlaybackState state);

  /// Current muxed audio + subtitle snapshot from the native ExoPlayer demuxer (embedded tracks only).
  void onMuxedTracksDiscovered(
    List<NativeMuxedAudioRow> audio,
    List<NativeMuxedSubtitleRow> subtitles,
  );

  /// ExoPlayer [PlaybackException] surfaced to Dart for Sentry / Crashlytics.
  void onPlaybackError(int errorCode, String errorCodeName, String? message);

  /// One decoded cue from the muxed text track, for the English/unknown script sniff.
  void onEmbeddedSubtitleCue(String text);
}

@FlutterApi()
abstract class VideoPlayerControlsCallback {
  void loadNextVideo();
  void loadPreviousVideo();
  void onStop();

  /// Belt-and-suspenders final-position report for the native (ExoPlayer/Telegram) path.
  ///
  /// [onStop] crosses from the native VideoPlayerActivity back into Dart's long-lived
  /// MainActivity engine via a Pigeon FlutterApi call issued from a Compose onDispose — a path
  /// that has been observed to silently not land (no log, no crash, no progress saved) on at
  /// least one real device. [clearSession] on the native side runs reliably regardless, so it
  /// calls this with the last known position/duration right before wiping state, giving Dart a
  /// second, independent chance to persist progress if [onStop] never arrived.
  void onPlaybackClosed(int positionMs, int durationMs);
  void swapSubtitleTrack(int value);
  void swapAudioTrack(int value);
  void loadProgram(GuideChannel selection);
  @async
  List<GuideProgram> fetchProgramsForChannel(String channelId);

  @async
  List<SushiOnlineSubtitlePack> searchSushiOnlineSubtitles();

  @async
  SushiSubtitleActionResult downloadSushiOnlineSubtitle(String tag, String fileName);

  @async
  SushiSubtitleActionResult autoLoadSushiSubtitle();

  @async
  SushiSubtitleActionResult translateSubtitleToPersian();

  /// Drop an in-flight Automatic / AI / Online load. Back and Esc on the busy dialog.
  void cancelSushiSubtitle();

  @async
  SushiAiKeySetup sushiAiKeySetup();
}
