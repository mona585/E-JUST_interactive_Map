import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../models/user_location.dart';

/// Visual marker widget displaying the user's real-time GPS location fix.
class UserLocationMarker extends StatefulWidget {
  final UserLocation location;

  const UserLocationMarker({
    super.key,
    required this.location,
  });

  @override
  State<UserLocationMarker> createState() => _UserLocationMarkerState();
}

class _UserLocationMarkerState extends State<UserLocationMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    _pulseAnimation = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeOutQuad,
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final heading = widget.location.heading;
    final hasHeading = heading > 0 && heading <= 360;

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return SizedBox(
          width: 48,
          height: 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Pulsing outer accuracy wave
              Transform.scale(
                scale: 1.0 + (_pulseAnimation.value * 0.8),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color.fromRGBO(
                      59,
                      130,
                      246,
                      (1.0 - _pulseAnimation.value) * 0.4,
                    ),
                  ),
                ),
              ),

              // Directional heading arrow if heading is known
              if (hasHeading)
                Transform.rotate(
                  angle: heading * (math.pi / 180),
                  child: Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.topCenter,
                    child: const CustomPaint(
                      size: Size(10, 8),
                      painter: _HeadingArrowPainter(),
                    ),
                  ),
                ),

              // Solid high-contrast GPS dot
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF2563EB),
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black45,
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HeadingArrowPainter extends CustomPainter {
  const _HeadingArrowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF2563EB)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}