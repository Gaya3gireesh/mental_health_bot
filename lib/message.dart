class Message {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final Map<String, dynamic>? crisisInfo;

  Message({
    required this.text, 
    required this.isUser, 
    DateTime? timestamp,
    this.crisisInfo,
  }) : timestamp = timestamp ?? DateTime.now();
}