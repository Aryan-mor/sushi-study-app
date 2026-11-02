import 'dart:async';

import 'package:chopper/chopper.dart';

import 'package:fladder/sushi/sushi_env.dart';

/// HTTP performance interceptor (Sentry spans removed — pass-through).
class SushiHttpPerformanceInterceptor implements Interceptor {
  @override
  FutureOr<Response<BodyType>> intercept<BodyType>(Chain<BodyType> chain) async {
    if (!SushiEnv.isEnabled) {
      return chain.proceed(chain.request);
    }
    return chain.proceed(chain.request);
  }
}
