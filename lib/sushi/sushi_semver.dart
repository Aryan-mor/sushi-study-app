/// Semver helpers for in-app update prompts (ADR 0019).
final class SushiSemver {
  const SushiSemver(
      {required this.major, required this.minor, required this.patch});

  final int major;
  final int minor;
  final int patch;

  static SushiSemver? parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final core = trimmed.split('+').first.split('-').first;
    final parts = core.split('.');
    if (parts.isEmpty) return null;

    final numbers = <int>[];
    for (final part in parts) {
      final value = int.tryParse(part);
      if (value == null || value < 0) return null;
      numbers.add(value);
    }

    while (numbers.length < 3) {
      numbers.add(0);
    }

    return SushiSemver(
      major: numbers[0],
      minor: numbers[1],
      patch: numbers[2],
    );
  }

  bool isNewerThan(SushiSemver other) {
    if (major != other.major) return major > other.major;
    if (minor != other.minor) return minor > other.minor;
    return patch > other.patch;
  }

  bool isMajorUpdateComparedTo(SushiSemver other) => major > other.major;

  /// Inverse of `android/app/build.gradle` `versionCode` formula.
  static SushiSemver? fromVersionCode(int code) {
    if (code < 0) return null;

    final major = code ~/ 100000;
    final remainder = code % 100000;
    final minor = remainder ~/ 1000;
    final patch = remainder % 1000;

    if (major == 0 && minor == 0 && patch == 0) return null;

    return SushiSemver(major: major, minor: minor, patch: patch);
  }

  @override
  String toString() => '$major.$minor.$patch';
}
