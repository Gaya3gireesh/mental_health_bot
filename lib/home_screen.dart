import 'package:flutter/material.dart';
import 'chat_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mental Health Support'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'How are you feeling today?',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 20,
                crossAxisSpacing: 20,
                children: [
                  _buildEmotionCard(
                    context,
                    'Happy',
                    Icons.sentiment_very_satisfied,
                    Colors.green,
                  ),
                  _buildEmotionCard(
                    context,
                    'Sad',
                    Icons.sentiment_dissatisfied,
                    Colors.blue,
                  ),
                  _buildEmotionCard(
                    context,
                    'Anxious',
                    Icons.psychology,
                    Colors.orange,
                  ),
                  _buildEmotionCard(
                    context,
                    'Stressed',
                    Icons.warning_amber,
                    Colors.red,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const ChatScreen(),
            ),
          );
        },
        child: const Icon(Icons.chat),
      ),
    );
  }

  Widget _buildEmotionCard(
    BuildContext context,
    String emotion,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: 4,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatScreen(initialEmotion: emotion),
            ),
          );
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 48,
              color: color,
            ),
            const SizedBox(height: 8),
            Text(
              emotion,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
