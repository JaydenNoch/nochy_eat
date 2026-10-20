import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Premium animated loading screen for NOCHY NOW.
///
/// White background, stationary circular logo, pink orbit spinner outside
/// the logo, and staggered LOADING text with sequential trailing dots.
class NochyLoadingScreen extends StatefulWidget {
  const NochyLoadingScreen({super.key});

  @override
  State<NochyLoadingScreen> createState() => _NochyLoadingScreenState();
}

class _NochyLoadingScreenState extends State<NochyLoadingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _spinnerCtrl;
  late final AnimationController _textCtrl;
  late final AnimationController _dotsCtrl;

  static const _pink = Color(0xFFD9138A);
  static const _logoSize = 120.0;
  static const _spinnerRadius = 80.0;

  @override
  void initState() {
    super.initState();

    _spinnerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    _textCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _dotsCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _spinnerCtrl.dispose();
    _textCtrl.dispose();
    _dotsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildLogoWithSpinner(),
            const SizedBox(height: 36),
            _buildLoadingText(),
            const SizedBox(height: 12),
            _buildSubtitle(),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoWithSpinner() {
    return SizedBox(
      width: _spinnerRadius * 2 + 20,
      height: _spinnerRadius * 2 + 20,
      child: AnimatedBuilder(
        animation: _spinnerCtrl,
        builder: (context, child) {
          return CustomPaint(
            painter: _OrbitSpinnerPainter(progress: _spinnerCtrl.value),
            child: child,
          );
        },
        child: Center(
          child: ClipOval(
            child: Image.asset(
              'lib/theme/logoeat.png',
              width: _logoSize,
              height: _logoSize,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  width: _logoSize,
                  height: _logoSize,
                  decoration: const BoxDecoration(
                    color: _pink,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.restaurant_rounded,
                    color: Colors.white,
                    size: 48,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingText() {
    const letters = ['L', 'O', 'A', 'D', 'I', 'N', 'G'];
    const letterCount = 7;

    return AnimatedBuilder(
      animation: _textCtrl,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < letterCount; i++) ...[
              _bounceLetter(letters[i], i),
              if (i < letterCount - 1) const SizedBox(width: 2),
            ],
            const SizedBox(width: 8),
            _buildDots(),
          ],
        );
      },
    );
  }

  Widget _bounceLetter(String letter, int index) {
    const stagger = 0.08;
    final delay = index * stagger;
    final progress = (_textCtrl.value - delay).clamp(0.0, 1.0);
    final bounce = math.sin(progress * math.pi) * 4.0;
    final opacity = 0.5 + 0.5 * math.sin(progress * math.pi);

    return Transform.translate(
      offset: Offset(0, -bounce),
      child: Opacity(
        opacity: opacity,
        child: Text(
          letter,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: _pink,
            letterSpacing: 4,
          ),
        ),
      ),
    );
  }

  Widget _buildDots() {
    return AnimatedBuilder(
      animation: _dotsCtrl,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final delay = i * 0.2;
            final progress = (_dotsCtrl.value - delay).clamp(0.0, 1.0);
            final opacity = 0.2 + 0.8 * math.sin(progress * math.pi);
            return Opacity(
              opacity: opacity,
              child: const Text(
                '.',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _pink,
                ),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildSubtitle() {
    return const Text(
      'Menyiapkan pengalaman NOCHY NOW',
      style: TextStyle(
        fontSize: 12,
        color: _pink,
        letterSpacing: 1,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

/// Paints a thin circular track with a rotating pink arc segment.
class _OrbitSpinnerPainter extends CustomPainter {
  final double progress;

  _OrbitSpinnerPainter({required this.progress});

  static const _pink = Color(0xFFD9138A);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Faint full track.
    final trackPaint = Paint()
      ..color = _pink.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    // Rotating arc segment (approx 90 degrees).
    final sweep = math.pi / 2;
    final start = progress * 2 * math.pi - math.pi / 2;

    final arcPaint = Paint()
      ..color = _pink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      start,
      sweep,
      false,
      arcPaint,
    );

    // Leading dot at the arc tip.
    final dotAngle = start + sweep;
    final dotOffset = Offset(
      center.dx + radius * math.cos(dotAngle),
      center.dy + radius * math.sin(dotAngle),
    );
    canvas.drawCircle(dotOffset, 3.5, Paint()..color = _pink);
  }

  @override
  bool shouldRepaint(_OrbitSpinnerPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
