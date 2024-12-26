import 'package:flutter/material.dart';

class CustomImageSpinner extends StatefulWidget {
  final double size;
  final Duration duration;
  final bool type;

  const CustomImageSpinner({
    super.key,
    this.size = 50.0,
    this.duration = const Duration(seconds: 1),
    this.type = true,
  });

  @override
  State<CustomImageSpinner> createState() => _CustomImageSpinnerState();
}

class _CustomImageSpinnerState extends State<CustomImageSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: Image.asset(
        widget.type
            ? 'assets/icons8_spinner_50.png'
            : 'assets/icons8_waiting.png',
        width: widget.size,
        height: widget.size,
      ),
    );
  }
}
