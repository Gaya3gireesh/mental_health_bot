import 'package:flutter/material.dart';

// Add an animating effect to the MoodIsland widget
class MoodIsland extends StatefulWidget {
  final String currentMood;

  const MoodIsland({
    super.key,
    required this.currentMood,
  });

  @override
  State<MoodIsland> createState() => _MoodIslandState();
}

class _MoodIslandState extends State<MoodIsland>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
        CurvedAnimation(parent: _controller, curve: Curves.elasticOut));

    // Start animation when widget builds
    _controller.forward();
  }

  @override
  void didUpdateWidget(MoodIsland oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentMood != widget.currentMood) {
      _controller.reset();
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Map moods to emojis
    final Map<String, String> moodEmojis = {
      'Happy': '😊',
      'Sad': '😔',
      'Angry': '😡',
      'Calm': '😌',
      'Anxious': '😰',
      'Neutral': '😐',
    };

    // Get emoji for current mood
    String emoji = moodEmojis[widget.currentMood] ?? '😐';

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: child,
        );
      },
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          constraints: const BoxConstraints(maxWidth: 200), // Set a max width
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(204),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(51), // 0.2 * 255 ≈ 51
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min, // This helps with minimizing width
            mainAxisAlignment: MainAxisAlignment.center, // Center contents
            children: [
              Text(emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Flexible(
                // Wrap in Flexible to allow text to shrink if needed
                child: Text(
                  widget.currentMood,
                  overflow:
                      TextOverflow.ellipsis, // Add ellipsis if text overflows
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
