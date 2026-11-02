import 'dart:async';

import 'package:chopper/chopper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Single-shot flag: next PlaybackInfo request includes X-OX-Force-Repair.
final sushiForceRepairNextPlaybackProvider = StateProvider<bool>((ref) => false);

const sushiForceRepairHeader = 'X-OX-Force-Repair';

/// Adds [sushiForceRepairHeader] on the next PlaybackInfo POST when the flag is set.
class SushiForceRepairInterceptor implements Interceptor {
  SushiForceRepairInterceptor(this.ref);

  final Ref ref;

  @override
  FutureOr<Response<BodyType>> intercept<BodyType>(Chain<BodyType> chain) async {
    final path = chain.request.url.path.toLowerCase();
    if (!path.contains('playbackinfo')) {
      return chain.proceed(chain.request);
    }

    final forceRepair = ref.read(sushiForceRepairNextPlaybackProvider);
    if (!forceRepair) {
      return chain.proceed(chain.request);
    }

    ref.read(sushiForceRepairNextPlaybackProvider.notifier).state = false;
    final headers = Map<String, String>.from(chain.request.headers);
    headers[sushiForceRepairHeader] = '1';
    return chain.proceed(chain.request.copyWith(headers: headers));
  }
}

void sushiArmForceRepairPlayback(Ref ref) {
  ref.read(sushiForceRepairNextPlaybackProvider.notifier).state = true;
}
