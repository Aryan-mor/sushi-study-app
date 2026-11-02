import 'package:flutter/widgets.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:fladder/models/view_model.dart';
import 'package:fladder/sushi/sushi_views.dart';
import 'package:fladder/util/localization_helper.dart';

/// OX-facing library folder labels (server [jellyfin.VirtualTVViewName] is source of truth).
abstract final class SushiViewLabels {
  static const tvLibraryName = 'Series';

  static ViewModel apply(ViewModel view) {
    
    if (view.collectionType != CollectionType.tvshows) return view;
    if (view.name == tvLibraryName) return view;
    return view.copyWith(name: tvLibraryName);
  }

  static List<ViewModel> applyAll(List<ViewModel> views) => views.map(apply).toList();
}

/// Drawer labels for the synthetic Sushi libraries. Stored [ViewModel.name] stays English.
String sushiSyntheticViewLabel(BuildContext context, ViewModel view) {
  final localized = context.localized;
  return switch (view.id) {
    sushiViewMovies => localized.sushiNavMovies,
    sushiViewSeries => localized.sushiNavSeries,
    sushiViewBoxsets => localized.sushiNavBoxSets,
    sushiViewPlaylists => localized.sushiNavPlaylists,
    _ => view.name,
  };
}
