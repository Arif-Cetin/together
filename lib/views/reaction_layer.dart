import 'dart:math';

import 'package:flutter/material.dart';

class FloatingReaction {
  final String id;
  final String emoji;
  final double leftPosition;

  FloatingReaction({
    required this.id,
    required this.emoji,
    required this.leftPosition,
  });
}

class ReactionLayer extends StatefulWidget {
  final List<FloatingReaction> reactions;

  const ReactionLayer({super.key, required this.reactions});

  @override
  State<ReactionLayer> createState() => _ReactionLayerState();
}

class _ReactionLayerState extends State<ReactionLayer>
    with TickerProviderStateMixin {
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: widget.reactions.map((reaction) {
          return _FloatingEmojiWidget(
            key: ValueKey(reaction.id),
            emoji: reaction.emoji,
            left: reaction.leftPosition,
          );
        }).toList(),
      ),
    );
  }
}

class _FloatingEmojiWidget extends StatefulWidget {
  final String emoji;
  final double left;

  const _FloatingEmojiWidget({
    super.key,
    required this.emoji,
    required this.left,
  });

  @override
  State<_FloatingEmojiWidget> createState() => _FloatingEmojiWidgetState();
}

class _FloatingEmojiWidgetState extends State<_FloatingEmojiWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..forward();

    _slideAnimation = Tween<double>(
      begin: 0,
      end: -350,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.5, end: 1.3), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 1.0), weight: 80),
    ]).animate(_controller);

    _fadeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 55),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 30),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Positioned(
          bottom: 40 - _slideAnimation.value,
          left: widget.left,
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: Transform.scale(
              scale: _scaleAnimation.value,
              child: Text(widget.emoji, style: const TextStyle(fontSize: 32)),
            ),
          ),
        );
      },
    );
  }
}
