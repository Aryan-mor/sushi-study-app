import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:fladder/sushi/models/sushi_media_issue_category.dart';
import 'package:fladder/sushi/models/sushi_media_issue_target.dart';

part 'sushi_media_issue_submit.g.dart';

@riverpod
class SushiMediaIssueSubmit extends _$SushiMediaIssueSubmit {
  @override
  FutureOr<void> build() {}

  Future<void> submit({
    required SushiMediaIssueTarget target,
    required SushiMediaIssueCategory category,
    String? customMessage,
  }) async {
    state = const AsyncLoading();
    state = AsyncError(
      StateError('Media issue reporting is unavailable'),
      StackTrace.current,
    );
  }
}
