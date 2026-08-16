import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../data/models/user_location.dart';

/// Visual marker widget displaying the user's real-time position fix (GPS or Indoor Wi-Fi).
class UserLocationMarker extends StatefulWidget {
  final UserLocation location;
  final bool isIndoor;

  const UserLocationMarker({
    super.key,
    required this.location,
    this.isIndoor = false,
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
    final isIndoor = widget.isIndoor;

    final primaryColor = isIndoor ? const Color(0xFF0D9488) : const Color(0xFF2563EB); // Teal for Indoor, Blue for GPS
    final waveColor = isIndoor ? const Color(0xFF14B8A6) : const Color(0xFF3B82F6);

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
                    color: waveColor.withValues(
                      alpha: (1.0 - _pulseAnimation.value) * 0.4,
                    ),
                  ),
                ),
              ),

              // Directional heading arrow if heading is known
              if (hasHeading && !isIndoor)
                Transform.rotate(
                  angle: heading * (math.pi / 180),
                  child: Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.topCenter,
                    child: CustomPaint(
                      size: const Size(10, 8),
                      painter: _HeadingArrowPainter(primaryColor),
                    ),
                  ),
                ),

              // Solid high-contrast user dot
              Container(
                width: isIndoor ? 22 : 18,
                height: isIndoor ? 22 : 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: primaryColor,
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
                  child: isIndoor
                      ? const Icon(
                          Icons.wifi,
                          size: 11,
                          color: Colors.white,
                        )
                      : Container(
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
  final Color color;
  const _HeadingArrowPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
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
