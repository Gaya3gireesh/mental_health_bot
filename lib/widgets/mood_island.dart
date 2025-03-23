import 'package:flutter/material.dart';

class MoodIsland extends StatelessWidget {
  final String currentMood;
  
  const MoodIsland({
    super.key, 
    required this.currentMood,
  });

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
    String emoji = moodEmojis[currentMood] ?? '😐';

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 200), // Set a max width
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(204),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(51),  // 0.2 * 255 ≈ 51
              blurRadius: 4,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min, // This helps with minimizing width
          mainAxisAlignment: MainAxisAlignment.center, // Center contents
          children: [
            Text(
              emoji, 
              style: const TextStyle(fontSize: 20)
            ),
            const SizedBox(width: 8),
            Flexible( // Wrap in Flexible to allow text to shrink if needed
              child: Text(
                currentMood,
                overflow: TextOverflow.ellipsis, // Add ellipsis if text overflows
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}