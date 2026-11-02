import 'package:flutter/material.dart';

/// Compatibility stub — Seerr product surface removed (Phase 2).
/// Kept so dart_mappable fields on Movie/Series/Person still type-check.
class SeerrDashboardPosterModel {
  final String id;
  final String title;
  final String? posterUrl;
  final String? releaseYear;
  final Color? displayStatusColor;

  const SeerrDashboardPosterModel({
    this.id = '',
    this.title = '',
    this.posterUrl,
    this.releaseYear,
    this.displayStatusColor,
  });
}
