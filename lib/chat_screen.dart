import 'package:flutter/material.dart';
import 'message.dart';

class ChatScreen extends StatefulWidget {
  final String? initialEmotion;

  const ChatScreen({super.key, this.initialEmotion});

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<Message> _messages = [];
  final _textController = TextEditingController();

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
    _textController.clear();

    setState(() {
      _messages.add(Message(text: text, isUser: true));
    });

    // Add chatbot response logic here
    // This is a simple example response
    Future.delayed(const Duration(seconds: 1), () {
      _addBotMessage("I hear you. Can you tell me more about that?");
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat with Support'),
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
