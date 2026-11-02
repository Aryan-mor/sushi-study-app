import 'package:flutter/material.dart';

import 'package:fladder/sushi/widgets/sushi_skeleton_box.dart';

/// Play-button-shaped skeleton for detail screens while item data loads.
class SushiMediaPlayButtonSkeleton extends StatelessWidget {
  const SushiMediaPlayButtonSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const SushiSkeletonBox(
      width: 148,
      height: 44,
      borderRadius: BorderRadius.all(Radius.circular(16)),
    );
  }
}
