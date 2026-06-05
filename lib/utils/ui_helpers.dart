import 'package:flutter/material.dart';

const serviceTitleTextStyle = TextStyle(
  fontSize: 17,
  fontWeight: FontWeight.w700,
  letterSpacing: .1,
);

TextStyle mutedTextStyle(BuildContext context) {
  return Theme.of(
    context,
  ).textTheme.bodyMedium!.copyWith(color: Colors.grey.shade700);
}

TextStyle sectionHeaderTextStyle(BuildContext context) {
  return Theme.of(context).textTheme.titleLarge!.copyWith(
    fontWeight: FontWeight.w700,
    letterSpacing: .1,
  );
}

class AccentCard extends StatelessWidget {
  final Color accentColor;
  final Color? color;
  final Widget child;
  final double elevation;
  final ShapeBorder? shape;

  const AccentCard({
    super.key,
    required this.accentColor,
    required this.child,
    this.color,
    this.elevation = 1,
    this.shape,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      color: color,
      elevation: elevation,
      shape: shape,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: accentColor.withValues(alpha: .8)),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
