import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io' show Platform;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'message.dart';
import 'resource_model.dart';
import 'widgets/mood_island.dart'; // Add this import

class ChatScreen extends StatefulWidget {
  final String? initialEmotion;
  final String? userId;

  const ChatScreen({super.key, this.initialEmotion, this.userId});

  @override
  ChatScreenState createState() => ChatScreenState();
}

class ChatScreenState extends State<ChatScreen> {
  final List<Message> _messages = [];
  final _textController = TextEditingController();
  bool _isLoading = false;
  List<MentalHealthResource> _resources = [];
  bool _isLoadingResources = false;
  bool _resourcesLoaded = false;
  String? _currentMood;

  @override
  void initState() {
    super.initState();
    
    // Set initial mood if provided
    if (widget.initialEmotion != null && widget.initialEmotion!.isNotEmpty) {
      _currentMood = widget.initialEmotion;
      print("Setting initial mood from emotion: $_currentMood");
      
      _addBotMessage(
          "I understand you're feeling ${widget.initialEmotion}. How can I help you today?");
    } else {
      _currentMood = 'Neutral'; // Default mood
      print("Setting default mood: $_currentMood");
      
      _addBotMessage("Hi! How can I help you today?");
    }
    
    // Load resources automatically when app starts
    _loadResources();
  }
  
  Future<void> _loadResources({bool refresh = false}) async {
    if (_isLoadingResources) return;
    
    setState(() {
      _isLoadingResources = true;
      
      // Only create placeholders if we don't have resources yet
      if (_resources.isEmpty) {
        _resources = List.generate(5, (index) => 
          MentalHealthResource(
            title: "Loading Resource ${index + 1}...",
            content: "Please wait while we load resources...",
            category: "Loading",
          )
        );
      }
    });
    
    String baseUrl = dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:5000';
    if (Platform.isIOS && baseUrl.contains('10.0.2.2')) {
      baseUrl = baseUrl.replaceAll('10.0.2.2', 'localhost');
    }
    
    try {
      // Only refresh from server if resources are empty or explicitly requested
      bool shouldRefresh = refresh || _resources.isEmpty || (_resources.length == 5 && _resources[0].title.contains("Loading"));
      
      final response = await http.get(
        Uri.parse('$baseUrl/resources?refresh=${shouldRefresh}'),
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('Connection timed out. Please check your server.');
        },
      );
      
      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(response.body);
        final List<dynamic> data = responseData['resources'] ?? [];
        
        setState(() {
          _resources = data.map((json) => MentalHealthResource(
            title: json['title'] ?? "Untitled Resource",
            content: json['content'] ?? "No content available.",
            category: json['category'] ?? 'General',
          )).toList();
          _resourcesLoaded = true;
          _isLoadingResources = false;
        });
        
        // If this was explicitly refreshed, show a confirmation
        if (refresh && mounted) {
          // Safe way to extract status information
          final status = responseData['status'];
          final inProgress = status is Map && status.containsKey('in_progress') ? 
              status['in_progress'] ?? false : false;
              
          final message = inProgress 
              ? 'Resources are being updated in the background'
              : 'Resources have been updated';
              
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
        }
      } else {
        print('Failed to load resources: ${response.statusCode}');
        setState(() {
          _isLoadingResources = false;
        });
      }
    } catch (e) {
      print('Error loading resources: $e');
      setState(() {
        _isLoadingResources = false;
      });
      
      // Only show an error message if it was an explicit refresh
      if (refresh && mounted) {
        // Safe error message without substring that was causing problems
        String errorMsg = 'Error loading resources';
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMsg)),
        );
      }
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
      
      // More flexible mood detection - check for any mood word
      final extractedMood = _extractMoodFromResponse(response);
      if (extractedMood.isNotEmpty) {
        print("Detected mood in response: $extractedMood");
        print("Full response: $response");
        
        setState(() {
          _currentMood = extractedMood;
          print("Updated current mood to: $_currentMood");
        });
      }
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
          'emotion': _currentMood ?? widget.initialEmotion ?? '', // Use current mood if available
          'user_id': widget.userId
        }),
      ).timeout(
        const Duration(seconds: 15), // Increased timeout
        onTimeout: () {
          throw TimeoutException('Connection timed out. Please check your server.');
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final botResponse = data['response'];
        
        // Add debug logging
        print("Bot response received: $botResponse");
        print("Looking for mood keywords in response...");
        
        // If message is asking about emotions or similar, add a mood prompt
        final lowerMessage = message.toLowerCase();
        if (lowerMessage.contains("feel") || 
            lowerMessage.contains("mood") ||
            lowerMessage.contains("emotion") ||
            lowerMessage.contains("how am i") ||
            lowerMessage.contains("how are you")) {
          
          // For these types of questions, force the bot to mention the current mood
          // This will help trigger mood detection
          final moodPrompt = "Based on our conversation, you seem to be feeling $_currentMood. ";
          return moodPrompt + botResponse;
        }
        
        return botResponse;
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
    return WillPopScope(
      onWillPop: () async {
        return true; // Allow the screen to be popped
      },
      child: Scaffold(
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
                      SnackBar(content: Text('Backend connected: ${data['message'] ?? "OK"}')),
                    );
                  }
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Connection error: Check your server')),
                  );
                }
              },
            ),
            // Add this to your AppBar actions list
            IconButton(
              icon: const Icon(Icons.save),
              tooltip: 'Current Mood',
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Current mood: $_currentMood')),
                );
              },
            ),
            // Inside your AppBar actions list in build method, add this new button:

            IconButton(
              icon: const Icon(Icons.mood),
              tooltip: 'Set Current Mood',
              onPressed: () {
                _showMoodSelectionDialog();
              },
            ),
          ],
        ),
        body: Column(
          children: [
            // Make sure this part of your build method is correct
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: MoodIsland(currentMood: _currentMood ?? 'Neutral'),
            ),
            
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
        // Add this to position the floating action button higher
        floatingActionButtonLocation: const CustomFloatingActionButtonLocation(80),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            // Show a loading snackbar
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Loading resources...'),
                duration: Duration(seconds: 1),
              ),
            );
            // Then show the resources dialog
            _showResourcesDialog();
          },
          tooltip: 'Mental Health Resources',
          child: const Icon(Icons.menu_book),
        ),
      ),
    );
  }
  
  void _showResourcesDialog() {
    // If resources are loaded and not loading, show the dialog immediately
    if (_resourcesLoaded && !_isLoadingResources) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return _buildResourcesDialog();
        }
      );
      return;
    }
    
    // If resources are currently loading (including from initState), show a loading dialog
    // that will automatically be replaced when loading is complete
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Loading Resources'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Please wait while we load mental health resources...')
            ],
          ),
        );
      },
    );
    
    // Keep track of this specific request
    bool dialogHandled = false;
    
    // Check if resources are already loading
    if (_isLoadingResources) {
      // Create a timer to periodically check if loading is complete
      Timer.periodic(const Duration(milliseconds: 500), (timer) {
        // If resources are loaded and timer is still active
        if (mounted && !dialogHandled && _resourcesLoaded && !_isLoadingResources) {
          dialogHandled = true;
          timer.cancel();
          
          // Replace the loading dialog with the resources dialog
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
            
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return _buildResourcesDialog();
              }
            );
          }
        }
        
        // Cancel timer after a reasonable timeout (10 seconds)
        if (timer.tick > 20) {
          timer.cancel();
          if (mounted && !dialogHandled) {
            dialogHandled = true;
            // Show error if loading took too long
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Loading resources is taking longer than expected. Try again later.')),
            );
          }
        }
      });
      return;
    }
    
    // If not currently loading, start loading resources
    dialogHandled = false;
    _loadResources(refresh: !_resourcesLoaded).then((_) {
      // Once resources are loaded, close the loading dialog and show resources dialog
      if (mounted && !dialogHandled) {
        dialogHandled = true;
        
        // First pop the loading dialog
        Navigator.of(context).pop();
        
        // Then show the resources dialog
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return _buildResourcesDialog();
          }
        );
      }
    }).catchError((error) {
      // Handle errors if resource loading fails
      if (mounted && !dialogHandled) {
        dialogHandled = true;
        
        // Close loading dialog
        Navigator.of(context).pop();
        
        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load resources. Please try again.')),
        );
      }
    });
  }
  
  Widget _buildResourcesDialog() {
    return AlertDialog(
      title: const Text('Mental Health Resources'),
      content: SizedBox(
        width: double.maxFinite,
        child: _isLoadingResources
            ? const Center(child: CircularProgressIndicator())
            : _resources.isEmpty
                ? const Text('No resources available.')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _resources.length,
                    itemBuilder: (context, index) {
                      final resource = _resources[index];
                      return ListTile(
                        title: Text(resource.title),
                        subtitle: Text(resource.category),
                        onTap: () {
                          Navigator.pop(context);
                          _showResourceContent(resource);
                        },
                      );
                    },
                  ),
      ),
      actions: <Widget>[
        TextButton(
          child: const Text('Close'),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
  
  void _showResourceContent(MentalHealthResource resource) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(resource.title),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Show category chip
                Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Chip(
                    label: Text(resource.category),
                    backgroundColor: Colors.blue.shade100,
                  ),
                ),
                // Show content text - safe handling
                Text(
                  resource.content.isEmpty ? 
                    "No content available at this time." : 
                    resource.content
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                // Close this dialog and show the resources list again
                Navigator.of(context).pop();
                showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return _buildResourcesDialog();
                  }
                );
              },
              child: const Text('Back'),
            ),
          ],
        );
      },
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

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  // Move this method INSIDE the ChatScreenState class
  String _extractMoodFromResponse(String response) {
    // Make lowercase for case-insensitive matching
    final lowerResponse = response.toLowerCase();
    
    // Map of mood keywords to return values
    final Map<String, List<String>> moodKeywords = {
      'Happy': ['happy', 'joy', 'glad', 'cheerful', 'delighted', 'pleased'],
      'Sad': ['sad', 'unhappy', 'depressed', 'down', 'blue', 'gloomy'],
      'Angry': ['angry', 'upset', 'frustrated', 'mad', 'furious', 'irritated'],
      'Calm': ['calm', 'relaxed', 'peaceful', 'tranquil', 'serene'],
      'Anxious': ['anxious', 'worried', 'nervous', 'stress', 'tense', 'uneasy'],
      'Neutral': ['neutral', 'fine', 'okay', 'alright']
    };
    
    // Find the first mood that matches any keyword
    for (final entry in moodKeywords.entries) {
      for (final keyword in entry.value) {
        if (lowerResponse.contains(keyword)) {
          print("Found mood keyword: $keyword, setting mood to: ${entry.key}");
          return entry.key;
        }
      }
    }
    
    // If no mood is found, don't change the current mood
    return '';
  }

  // Add this new method to your ChatScreenState class

  void _showMoodSelectionDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return SimpleDialog(
          title: const Text('Select your current mood'),
          children: <Widget>[
            _buildMoodOption('Happy', '😊'),
            _buildMoodOption('Sad', '😔'),
            _buildMoodOption('Angry', '😡'),
            _buildMoodOption('Calm', '😌'),
            _buildMoodOption('Anxious', '😰'),
            _buildMoodOption('Neutral', '😐'),
          ],
        );
      },
    );
  }

  Widget _buildMoodOption(String mood, String emoji) {
    return SimpleDialogOption(
      onPressed: () {
        Navigator.pop(context);
        setState(() {
          _currentMood = mood;
          print("Manually set mood to: $_currentMood");
        });
        
        // Show confirmation
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Mood set to: $mood')),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 16),
            Text(mood, style: const TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }
}

// Add this class at the top level of your file (outside any other classes)
class CustomFloatingActionButtonLocation extends FloatingActionButtonLocation {
  final double offsetY;
  
  const CustomFloatingActionButtonLocation(this.offsetY);
  
  @override
  Offset getOffset(ScaffoldPrelayoutGeometry scaffoldGeometry) {
    // Get the default position from endFloat
    final Offset offset = FloatingActionButtonLocation.endFloat.getOffset(scaffoldGeometry);
    
    // Return a new position with adjusted Y
    return Offset(offset.dx, offset.dy - offsetY);
  }
}
