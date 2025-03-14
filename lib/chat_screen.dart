import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io' show Platform;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'message.dart';

class ChatScreen extends StatefulWidget {
  final String? initialEmotion;

  const ChatScreen({super.key, this.initialEmotion});

  @override
  ChatScreenState createState() => ChatScreenState();
}

class ChatScreenState extends State<ChatScreen> {
  final List<Message> _messages = [];
  final _textController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialEmotion != null) {
      _addBotMessage(
          "I understand you're feeling ${widget.initialEmotion}. How can I help you today?");
    } else {
      _addBotMessage("Hi! How can I help you today?");
    }
  }

  void _addBotMessage(String text) {
    setState(() {
      _messages.add(Message(text: text, isUser: false));
    });
  }

  void _handleSubmitted(String text) {
    if (text.trim().isEmpty) return;
    
    _textController.clear();

    setState(() {
      _messages.add(Message(text: text, isUser: true));
      _isLoading = true;
    });

    // Call backend API
    _getBotResponse(text).then((response) {
      setState(() {
        _isLoading = false;
        _addBotMessage(response);
      });
    }).catchError((error) {
      setState(() {
        _isLoading = false;
        _addBotMessage("Sorry, I'm having trouble connecting right now. Please try again later.");
      });
      print("Error connecting to backend: $error");
    });
  }

  Future<String> _getBotResponse(String message) async {
    // Get base URL from .env file with fallback
    String baseUrl = dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:5000';
    
    // If on iOS and using default Android emulator address, replace with localhost
    if (Platform.isIOS && baseUrl.contains('10.0.2.2')) {
      baseUrl = baseUrl.replaceAll('10.0.2.2', 'localhost');
    }
    
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'message': message,
          'emotion': widget.initialEmotion ?? '',
        }),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Connection timed out. Please check your server.');
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['response'];
      } else {
        throw Exception('Failed to load response: ${response.statusCode}');
      }
    } catch (e) {
      print('Error in API call: $e');
      if (e is TimeoutException) {
        return "Sorry, the server is taking too long to respond. Please try again later.";
      }
      throw e;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat with Support'),
        actions: [
          // Add this test button to the app bar
          IconButton(
            icon: const Icon(Icons.network_check),
            tooltip: 'Test Connection',
            onPressed: () async {
              try {
                final response = await http.get(
                  Uri.parse('${dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:5000'}/test_connection')
                );
                if (response.statusCode == 200) {
                  final data = json.decode(response.body);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Backend connected: ${data['message']}')),
                  );
                }
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Connection error: $e')),
                );
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8.0),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return _buildMessage(message);
              },
            ),
          ),
          if (_isLoading) 
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: const Center(child: CircularProgressIndicator()),
            ),
          _buildMessageComposer(),
        ],
      ),
    );
  }

  Widget _buildMessage(Message message) {
    return Container(
      margin: EdgeInsets.only(
        top: 8.0,
        bottom: 8.0,
        left: message.isUser ? 64.0 : 8.0,
        right: message.isUser ? 8.0 : 64.0,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      decoration: BoxDecoration(
        color: message.isUser ? Colors.blue : Colors.grey[300],
        borderRadius: BorderRadius.circular(20.0),
      ),
      child: Text(
        message.text,
        style: TextStyle(
          color: message.isUser ? Colors.white : Colors.black,
        ),
      ),
    );
  }

  Widget _buildMessageComposer() {
    return Container(
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          top: BorderSide(color: Colors.grey[200]!),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              decoration: const InputDecoration(
                hintText: 'Type a message...',
                border: InputBorder.none,
              ),
              onSubmitted: _handleSubmitted,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: () => _handleSubmitted(_textController.text),
          ),
        ],
      ),
    );
  }
}
