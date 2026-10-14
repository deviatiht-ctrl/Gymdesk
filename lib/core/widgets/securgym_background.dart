import 'package:flutter/material.dart';

/// Fond ofisyèl responsif SecurGYM.
/// Chwazi otomatikman:
/// - `background_desktop.jpeg` pou laptop, desktop ak ekran laj (>= 768px)
/// - `background_mobile.jpeg` pou telefòn ak tablèt pòtrè (< 768px)
class SecurGymBackground extends StatelessWidget {
  const SecurGymBackground({
    super.key,
    required this.child,
    this.overlayOpacity = 0.0,
    this.overlayColor = Colors.black,
    this.useSafeArea = true,
  });

  final Widget child;

  /// Opasite yon kouch si ou bezwen plis kontras sou tèks la (ant 0.0 ak 1.0)
  final double overlayOpacity;

  /// Koulè kouch overlay la
  final Color overlayColor;

  /// Si wi ou non pou vlope nan SafeArea
  final bool useSafeArea;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 768;
        final assetPath = isWide
            ? 'assets/brand/background_desktop.jpeg'
            : 'assets/brand/background_mobile.jpeg';

        final content = useSafeArea ? SafeArea(child: child) : child;

        return Stack(
          fit: StackFit.expand,
          children: [
            // Imaj fond responsif
            Positioned.fill(
              child: Image.asset(
                assetPath,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                errorBuilder: (_, _, _) => Container(
                  color: const Color(0xff121417),
                ),
              ),
            ),

            // Kouch overlay opsyonèl pou kontras
            if (overlayOpacity > 0.0)
              Positioned.fill(
                child: Container(
                  color: overlayColor.withValues(alpha: overlayOpacity),
                ),
              ),

            // Kontni prensipal la
            Positioned.fill(child: content),
          ],
        );
      },
    );
  }
}
