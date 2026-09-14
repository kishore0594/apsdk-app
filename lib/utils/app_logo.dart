import 'package:flutter/material.dart';

/// The Madhura Agro Traders logo: a rice-paddy sunset emblem with a
/// banyan tree, ringed by cattlefeed/millet/rice motifs.
///
/// Loaded from assets/logo.png (declared in pubspec.yaml). Kept behind
/// this small wrapper — rather than calling Image.asset directly in every
/// screen — so the logo can be swapped or adjusted in one place later.
class AppLogo extends StatelessWidget {
  final double size;

  /// Kept for compatibility with existing call sites (the image is a
  /// self-contained circular badge, so it doesn't need a separate
  /// background treatment the way the old hand-drawn mark did).
  final bool withBackground;

  const AppLogo({super.key, this.size = 64, this.withBackground = true});

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Image.asset(
        'assets/logo.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }
}
