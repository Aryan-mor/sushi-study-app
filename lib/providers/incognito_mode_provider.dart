import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

final incognitoModeProvider = StateProvider<bool>((ref) => kDebugMode);

// Sushi's AccountModel has no per-account incognitoMode override (unlike upstream Fladder),
// so this just mirrors the global toggle.
final incognitoProvider = Provider<bool>((ref) => ref.watch(incognitoModeProvider));
