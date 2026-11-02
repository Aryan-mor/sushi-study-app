import 'package:chopper/chopper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/items/person_model.dart';
import 'package:fladder/sushi/sushi_item_adapter.dart';
import 'package:fladder/sushi/sushi_list_transport.dart';

final personDetailsProvider =
    StateNotifierProvider.autoDispose.family<PersonDetailsNotifier, PersonModel?, String>((ref, id) {
  return PersonDetailsNotifier(ref);
});

class PersonDetailsNotifier extends StateNotifier<PersonModel?> {
  PersonDetailsNotifier(this.ref) : super(null) {
    ref.onDispose(() => _disposed = true);
  }

  final Ref ref;
  var _disposed = false;

  Future<Response?> fetchPerson(Person person) async {
    if (_disposed) return null;
    state = sushiPersonModel(person);
    final tmdbId = sushiPersonTmdbIdFromId(person.id);
    if (tmdbId == null) {
      debugPrint('[sushi] person: missing tmdb_id id=${person.id}');
      return null;
    }
    final page = await sushiFetchPerson(tmdbId: tmdbId);
    if (_disposed) return null;
    if (page == null) {
      debugPrint('[sushi] person: fetch returned null tmdbId=$tmdbId');
      return null;
    }
    state = sushiPersonModel(person, page: page);
    return null;
  }

  Future<void> toggleFavorite() async {
    // Sushi person favourites not wired yet.
  }
}
