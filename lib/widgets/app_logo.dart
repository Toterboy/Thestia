import 'package:flutter/material.dart';

/// App-Logo für Thestia — das abgerundete Standard-Logo
/// (`thestia_icon_base.png`, Ecken transparent gebacken).
///
/// Bewusst OHNE ClipOval: Das Artwork bringt seine eigene Rounded-Square-
/// Form mit. (Für Splash/Benachrichtigungen wird das runde Logo genutzt,
/// siehe tool/generate_branding.dart.)
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 120});

  final double size;

  @override
  Widget build(BuildContext context) {
    final pixelRatio = MediaQuery.of(context).devicePixelRatio;
    final cacheDim = (size * pixelRatio).toInt();
    return RepaintBoundary(
      child: Image.asset(
        'assets/images/thestia_icon_base.png',
        width: size,
        height: size,
        cacheWidth: cacheDim,
        cacheHeight: cacheDim,
        fit: BoxFit.contain,
        gaplessPlayback: true,
      ),
    );
  }
}
