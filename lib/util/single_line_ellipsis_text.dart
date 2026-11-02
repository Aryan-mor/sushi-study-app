import 'package:flutter/material.dart';

/// Single-line label with trailing ellipsis. Use inside [Flexible] / [Expanded] in a [Row].
Widget singleLineEllipsisText(
  String text, {
  TextStyle? style,
  TextAlign textAlign = TextAlign.start,
}) {
  return Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    softWrap: false,
    style: style,
    textAlign: textAlign,
  );
}
