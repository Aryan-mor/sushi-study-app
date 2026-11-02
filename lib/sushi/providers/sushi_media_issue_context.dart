import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:fladder/sushi/models/sushi_media_issue_target.dart';

part 'sushi_media_issue_context.g.dart';

class SushiMediaIssueContext {
  final int mediaId;
  final String title;
  final String? posterPath;

  const SushiMediaIssueContext({
    required this.mediaId,
    required this.title,
    this.posterPath,
  });
}

/// Seerr-backed media issues removed — always unavailable.
@riverpod
Future<SushiMediaIssueContext> sushiMediaIssueContext(
  SushiMediaIssueContextRef ref,
  SushiMediaIssueTarget target,
) async {
  throw StateError('Media issue reporting is unavailable');
}
