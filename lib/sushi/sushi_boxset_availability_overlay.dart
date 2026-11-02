import 'package:flutter/material.dart';

import 'package:fladder/models/boxset_model.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

const _tagCollectionComplete = 'sushi-collection-complete';
const _tagCollectionPartial = 'sushi-collection-partial';
const _tagCollectionMissing = 'sushi-collection-missing';
const _tagCatalogAvailable = 'sushi-catalog-available';
const _tagCatalogMissing = 'sushi-catalog-missing';

/// Seerr-style top-right badge for box set shelf cards and collection movie tiles.
Widget? sushiCatalogAvailabilityOverlay(ItemBaseModel poster) {
  
  final tags = poster.overview.tags;
  if (tags.isEmpty) return null;

  final bool? available;
  if (tags.contains(_tagCollectionComplete) || tags.contains(_tagCatalogAvailable)) {
    available = true;
  } else if (tags.contains(_tagCollectionPartial)) {
    available = null;
  } else if (tags.contains(_tagCollectionMissing) || tags.contains(_tagCatalogMissing)) {
    available = false;
  } else {
    return null;
  }
  if (available == null && !tags.contains(_tagCollectionPartial)) {
    return null;
  }

  final Color color;
  final IconData icon;
  if (available == true) {
    color = Colors.green.shade700;
    icon = IconsaxPlusLinear.import_3;
  } else if (available == false) {
    color = Colors.red.shade700;
    icon = Icons.remove_rounded;
  } else {
    color = Colors.orange.shade800;
    icon = IconsaxPlusLinear.box;
  }

  return Align(
    alignment: Alignment.topRight,
    child: Padding(
      padding: const EdgeInsets.all(6),
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
      ),
    ),
  );
}

bool sushiIsBoxSetShelfItem(ItemBaseModel item) => item is BoxSetModel;
