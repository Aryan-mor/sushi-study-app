import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:fladder/sushi/sushi_env.dart';
import 'package:fladder/sushi/sushi_provider_read.dart';
import 'package:fladder/sushi/providers/sushi_watchlist_dashboard.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/views_provider.dart';
import 'package:fladder/providers/user_provider.dart';

part 'sushi_tmdb_interest.g.dart';

enum SushiTmdbMediaType { movie, tv }

class SushiTmdbInterestState {
  final bool following;
  final bool watchlisted;
  final bool favorited;

  const SushiTmdbInterestState({
    this.following = false,
    this.watchlisted = false,
    this.favorited = false,
  });
}

String sushiTmdbMediaTypeApiValue(SushiTmdbMediaType type) {
  return switch (type) {
    SushiTmdbMediaType.movie => 'movie',
    SushiTmdbMediaType.tv => 'tv',
  };
}

Map<String, String> _sushiAuthHeaders(SushiRead read) {
  final credentials = read(userProvider)?.credentials;
  if (credentials == null) return const {};
  return {
    ...sushiMediaBrowserHeaders(read, credentials),
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };
}

@riverpod
class SushiTmdbInterest extends _$SushiTmdbInterest {
  @override
  Future<SushiTmdbInterestState> build(int tmdbId, SushiTmdbMediaType mediaType) async {
    if (!SushiEnv.isEnabled || tmdbId <= 0) {
      return const SushiTmdbInterestState();
    }
    final baseUrl = ref.read(serverUrlProvider);
    final credentials = ref.read(userProvider)?.credentials;
    if (baseUrl == null || baseUrl.isEmpty || credentials == null || credentials.token.trim().isEmpty) {
      return const SushiTmdbInterestState();
    }

    final apiMedia = sushiTmdbMediaTypeApiValue(mediaType);
    final uri = Uri.parse('$baseUrl/me/tmdb-interests/$apiMedia/$tmdbId');
    final response = await http.get(uri, headers: _sushiAuthHeaders(ref.read));
    if (response.statusCode != 200) {
      developer.log(
        'GET ${uri.path} failed status=${response.statusCode} body=${response.body}',
        name: 'SushiTmdbInterest',
      );
      return const SushiTmdbInterestState();
    }
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) return const SushiTmdbInterestState();
    return SushiTmdbInterestState(
      following: body['following'] == true,
      watchlisted: body['watchlisted'] == true,
      favorited: body['favorited'] == true,
    );
  }

  Future<bool> setFollowing(bool following, {String title = '', String posterUrl = ''}) {
    return _patch(following: following, title: title, posterUrl: posterUrl);
  }

  Future<bool> setWatchlisted(bool watchlisted, {String title = '', String posterUrl = ''}) {
    return _patch(watchlisted: watchlisted, title: title, posterUrl: posterUrl);
  }

  Future<bool> setFavorited(bool favorited, {String title = '', String posterUrl = ''}) {
    return _patch(favorited: favorited, title: title, posterUrl: posterUrl);
  }

  Future<bool> _patch({
    bool? following,
    bool? watchlisted,
    bool? favorited,
    String title = '',
    String posterUrl = '',
  }) async {
    if (!SushiEnv.isEnabled || tmdbId <= 0) return false;
    final baseUrl = ref.read(serverUrlProvider);
    final credentials = ref.read(userProvider)?.credentials;
    if (baseUrl == null || baseUrl.isEmpty || credentials == null || credentials.token.trim().isEmpty) {
      return false;
    }

    final apiMedia = sushiTmdbMediaTypeApiValue(mediaType);
    final uri = Uri.parse('$baseUrl/me/tmdb-interests/$apiMedia/$tmdbId');
    final payload = <String, dynamic>{
      if (following != null) 'following': following,
      if (watchlisted != null) 'watchlisted': watchlisted,
      if (favorited != null) 'favorited': favorited,
      if (title.isNotEmpty) 'title': title,
      if (posterUrl.isNotEmpty) 'posterUrl': posterUrl,
    };
    final response = await http.put(
      uri,
      headers: _sushiAuthHeaders(ref.read),
      body: jsonEncode(payload),
    );
    if (response.statusCode != 200) {
      developer.log(
        'PUT ${uri.path} failed status=${response.statusCode} body=${response.body}',
        name: 'SushiTmdbInterest',
      );
      return false;
    }
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) return false;
    state = AsyncData(
      SushiTmdbInterestState(
        following: body['following'] == true,
        watchlisted: body['watchlisted'] == true,
        favorited: body['favorited'] == true,
      ),
    );
    if (watchlisted != null) {
      sushiResetWatchlistHomeFeedRef(ref);
      ref.invalidate(sushiWatchlistDashboardProvider);
      unawaited(ref.read(viewsProvider.notifier).fetchViews());
    }
    return true;
  }
}
