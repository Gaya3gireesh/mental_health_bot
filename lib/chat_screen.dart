import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io' show Platform, SocketException, HttpException;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mental_health_bot/therapist_page.dart';
import 'message.dart';
import 'resource_model.dart';
import 'widgets/mood_island.dart';

class ChatScreen extends StatefulWidget {
  final String? initialEmotion;
  final String? userId;

  const ChatScreen({super.key, this.initialEmotion, this.userId});

  @override
  ChatScreenState createState() => ChatScreenState();
}

class ChatScreenState extends State<ChatScreen>
    with SingleTickerProviderStateMixin {
  final List<Message> _messages = [];
  final _textController = TextEditingController();
  bool _isLoading = false;
  bool _isChatting = false; // To track if the user has started chatting
  List<MentalHealthResource> _resources = [];
  bool _isLoadingResources = false;
  bool _resourcesLoaded = false;
  String? _currentMood;
  Map<String, dynamic>? _currentCrisisInfo;

  // Initialize with a default value to prevent late initialization error
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation = const AlwaysStoppedAnimation(1.0);

  @override
  void initState() {
    super.initState();

    // Initialize animation controller
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    // Now set the proper animation
    _fadeAnimation =
        Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    // Set initial mood if provided, with better logging
    if (widget.initialEmotion != null && widget.initialEmotion!.isNotEmpty) {
      _currentMood = widget.initialEmotion;
      print("Setting initial mood from emotion parameter: $_currentMood");

      _addBotMessage(
          "I understand you're feeling ${widget.initialEmotion}. How can I help you today?");
    } else {
      _currentMood = 'Neutral'; // Default mood
      print("Setting default initial mood: $_currentMood");

      _addBotMessage("Hi! How can I help you today?");
    }

    // Load resources automatically when app starts
    _loadResources();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _loadResources({bool refresh = false}) async {
    if (_isLoadingResources) return;

    setState(() {
      _isLoadingResources = true;

      // Only create placeholders if we don't have resources yet
      if (_resources.isEmpty) {
        _resources = List.generate(
            5,
            (index) => MentalHealthResource(
                  title: "Loading Resource ${index + 1}...",
                  content: "Please wait while we load resources...",
                  category: "Loading",
                ));
      }
    });

    String baseUrl = dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:5000';
    if (Platform.isIOS && baseUrl.contains('10.0.2.2')) {
      baseUrl = baseUrl.replaceAll('10.0.2.2', 'localhost');
    }

    try {
      // Only refresh from server if resources are empty or explicitly requested
      bool shouldRefresh = refresh ||
          _resources.isEmpty ||
          (_resources.length == 5 && _resources[0].title.contains("Loading"));

      final response = await http
          .get(
        Uri.parse('$baseUrl/resources?refresh=${shouldRefresh}'),
      )
          .timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException(
              'Connection timed out. Please check your server.');
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(response.body);
        final List<dynamic> data = responseData['resources'] ?? [];

        setState(() {
          _resources = data
              .map((json) => MentalHealthResource(
                    title: json['title'] ?? "Untitled Resource",
                    content: json['content'] ?? "No content available.",
                    category: json['category'] ?? 'General',
                  ))
              .toList();
          _resourcesLoaded = true;
          _isLoadingResources = false;
        });

        // If this was explicitly refreshed, show a confirmation
        if (refresh && mounted) {
          // Safe way to extract status information
          final status = responseData['status'];
          final inProgress = status is Map && status.containsKey('in_progress')
              ? status['in_progress'] ?? false
              : false;

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

  void _addBotMessage(String text, {Map<String, dynamic>? crisisInfo}) {
    setState(() {
      _messages.add(Message(
        text: text,
        isUser: false,
        crisisInfo: crisisInfo,
      ));

      // Store the most recent crisis info
      if (crisisInfo != null) {
        _currentCrisisInfo = crisisInfo;
      }
    });
  }

  void _handleSubmitted(String text) {
    if (text.trim().isEmpty) return;

    _textController.clear();

    setState(() {
      _messages.add(Message(text: text, isUser: true));
      _isLoading = true;
      _isChatting = true; // Transition to chat layout
    });

    // Start animation when transitioning to chat layout
    _animationController.forward();

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

        // Use our new method to update the mood
        _updateMood(extractedMood);
      }
    }).catchError((error) {
      setState(() {
        _isLoading = false;
        _addBotMessage(
            "Sorry, I'm having trouble connecting right now. Please try again later.");
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
      final response = await http
          .post(
        Uri.parse('$baseUrl/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'message': message,
          'emotion': _currentMood ??
              widget.initialEmotion ??
              '', // Use current mood if available
          'user_id': widget.userId
        }),
      )
          .timeout(
        const Duration(seconds: 15), // Increased timeout
        onTimeout: () {
          throw TimeoutException(
              'Connection timed out. Please check your server.');
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final botResponse = data['response'];

        // Check if crisis was detected
        final bool crisisDetected = data['crisis_detected'] ?? false;

        if (crisisDetected) {
          // Extract crisis information
          final crisisType = data['crisis_type'] as String?;
          final crisisScore = data['crisis_score'] as double?;
          final crisisResources = data['crisis_resources'] as String?;

          // Log crisis information
          print('Crisis detected: $crisisType with score: $crisisScore');

          // Store crisis information for display
          _currentCrisisInfo = {
            'type': crisisType ?? 'unknown',
            'score': crisisScore ?? 0.0,
            'resources': crisisResources ?? ''
          };

          // Show crisis alert
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _showCrisisAlert(
                  context, crisisType ?? 'crisis', crisisResources ?? '');
            }
          });
        }

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
          final moodPrompt =
              "Based on our conversation, you seem to be feeling $_currentMood. ";
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

  Future<void> _testBackendConnection() async {
    // Show a loading indicator
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Testing backend connection...')));

    // Get base URL from .env file with fallback
    String baseUrl = dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:5000';

    // If on iOS and using default Android emulator address, replace with localhost
    if (Platform.isIOS && baseUrl.contains('10.0.2.2')) {
      baseUrl = baseUrl.replaceAll('10.0.2.2', 'localhost');
    }

    print('Testing connection to: $baseUrl');

    // Try multiple endpoint tests in sequence
    try {
      // First try a simple ping test (priority)
      print('Attempting to connect to $baseUrl/test_connection');

      final response = await http.get(
        Uri.parse('$baseUrl/test_connection'),
        headers: {'Accept': 'application/json'}, // Added explicit headers
      ).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          print('Connection request timed out after 5 seconds');
          throw TimeoutException(
              'Connection timed out. Please check your server.');
        },
      );

      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        // Try to decode the JSON to verify it's valid
        try {
          final responseData = jsonDecode(response.body);
          final status = responseData['status'] ?? 'unknown';
          final message = responseData['message'] ?? 'No message provided';

          print('Connection successful! Status: $status, Message: $message');

          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Backend connection successful! $message'),
            backgroundColor: Colors.green,
          ));
        } catch (e) {
          print('Error parsing response: $e');
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Backend responded but with invalid JSON format'),
            backgroundColor: Colors.orange,
          ));
        }
      } else {
        print('Error status code: ${response.statusCode}');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Backend responded with error: ${response.statusCode}'),
          backgroundColor: Colors.orange,
        ));
      }
    } catch (e) {
      print('Connection test error: $e');

      // Try to provide more specific error information
      String errorMessage = 'Connection failed: ';

      if (e is SocketException) {
        errorMessage += 'Network error (server might be down or unreachable)';
        print(
            'Socket Exception details: ${e.message}, Address: ${e.address}, Port: ${e.port}');
      } else if (e is TimeoutException) {
        errorMessage += 'Request timed out';
      } else if (e is HttpException) {
        errorMessage += 'HTTP error: ${e.message}';
      } else if (e is FormatException) {
        errorMessage += 'Invalid response format: ${e.message}';
      } else {
        errorMessage += e.toString();
      }

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(errorMessage),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 8),
      ));

      // Show a dialog with connection troubleshooting tips
      _showConnectionTroubleshootingDialog(baseUrl);
    }
  }

  void _showConnectionTroubleshootingDialog(String baseUrl) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Connection Troubleshooting'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Here are some steps to try:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('1. Make sure your Flask server is running'),
                const Text('2. Check your API_BASE_URL in .env file'),
                const Text('3. If using an emulator, ensure 10.0.2.2 is used'),
                const Text(
                    '4. If using a physical device, use your computer\'s IP'),
                const Text('5. Check if any firewall is blocking connections'),
                const Text('6. Restart both the server and the app'),
                const SizedBox(height: 12),
                const Text('Current connection details:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('API URL: $baseUrl',
                    style: const TextStyle(fontFamily: 'monospace')),
                const SizedBox(height: 4),
                Text(
                    'Device type: ${Platform.isAndroid ? "Android" : Platform.isIOS ? "iOS" : "Other"}'),
                const SizedBox(height: 4),
                Text(
                    'Using emulator address: ${baseUrl.contains('10.0.2.2') ? "Yes" : "No"}'),
                const SizedBox(height: 16),
                const Text('Try these alternative URLs:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('• http://10.0.2.2:5000 (Android emulator)'),
                const Text('• http://localhost:5000 (iOS simulator)'),
                const Text(
                    '• http://<your-computer-ip>:5000 (Physical device)'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  _tryAlternativeConnection('http://10.0.2.2:5000'),
              child: const Text('Try 10.0.2.2'),
            ),
            TextButton(
              onPressed: () =>
                  _tryAlternativeConnection('http://localhost:5000'),
              child: const Text('Try localhost'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _tryAlternativeConnection(String alternativeUrl) async {
    Navigator.of(context).pop(); // Close the current dialog

    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Trying connection to $alternativeUrl...')));

    try {
      final response = await http
          .get(
            Uri.parse('$alternativeUrl/test_connection'),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Connection to $alternativeUrl successful!'),
          backgroundColor: Colors.green,
        ));

        // Show dialog with next steps
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Connection Successful'),
            content:
                Text('The connection to $alternativeUrl was successful!\n\n'
                    'Consider updating your .env file with:\n'
                    'API_BASE_URL=$alternativeUrl'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Connection to $alternativeUrl failed with status: ${response.statusCode}'),
          backgroundColor: Colors.red,
        ));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Connection to $alternativeUrl failed: ${e.toString().split('\n')[0]}'),
        backgroundColor: Colors.red,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: const Text(
          'Daily Reflection',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(
            icon: const Icon(Icons.network_check),
            onPressed: _testBackendConnection,
            tooltip: 'Test Connection',
          ),
          IconButton(
            icon: const Icon(Icons.mood),
            onPressed: _showMoodSelectionDialog,
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showResourcesDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          // Greeting Section
          if (!_isChatting) _buildGreetingSection(),

          // Dynamic Island Section - Key fix is here
          if (_isChatting)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: MoodIsland(
                  key: ValueKey(_currentMood ??
                      'Neutral'), // This ensures a rebuild when mood changes
                  currentMood: _currentMood ?? 'Neutral',
                ),
              ),
            ),

          // Chat Messages Section
          if (_isChatting)
            Expanded(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Stack(
                  children: [
                    ListView.builder(
                      padding: const EdgeInsets.all(8.0),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final message = _messages[index];
                        return _buildMessage(message);
                      },
                    ),
                    if (_isLoading)
                      const Center(
                        child: CircularProgressIndicator(),
                      ),
                  ],
                ),
              ),
            ),

          // Message Composer
          _buildMessageComposer(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        onTap: (index) {
          if (index == 1) {
            // Navigate to therapist page
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const TherapistPage()),
            );
          }
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Therapists',
          ),
        ],
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
          });
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
        if (mounted &&
            !dialogHandled &&
            _resourcesLoaded &&
            !_isLoadingResources) {
          dialogHandled = true;
          timer.cancel();

          // Replace the loading dialog with the resources dialog
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();

            showDialog(
                context: context,
                builder: (BuildContext context) {
                  return _buildResourcesDialog();
                });
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
              const SnackBar(
                  content: Text(
                      'Loading resources is taking longer than expected. Try again later.')),
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
            });
      }
    }).catchError((error) {
      // Handle errors if resource loading fails
      if (mounted && !dialogHandled) {
        dialogHandled = true;

        // Close loading dialog
        Navigator.of(context).pop();

        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Failed to load resources. Please try again.')),
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
                Text(resource.content.isEmpty
                    ? "No content available at this time."
                    : resource.content),
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
                    });
              },
              child: const Text('Back'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMessage(Message message) {
    // Check if this message is associated with a crisis
    final bool isCrisisMessage = !message.isUser && _currentCrisisInfo != null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: EdgeInsets.only(
        top: 8.0,
        bottom: 8.0,
        left: message.isUser ? 64.0 : 8.0,
        right: message.isUser ? 8.0 : 64.0,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      decoration: BoxDecoration(
        color: message.isUser
            ? Colors.blue
            : (isCrisisMessage ? Colors.orange.shade50 : Colors.white),
        borderRadius: BorderRadius.circular(20.0),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message.text,
            style: TextStyle(
              color: message.isUser ? Colors.white : Colors.black87,
            ),
          ),

          // Add help button for crisis messages
          if (isCrisisMessage) ...[
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 4),
            InkWell(
              onTap: () => _showCrisisResourcesDetails(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.help_outline,
                      color: Colors.red.shade400, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    'Important resources available',
                    style: TextStyle(
                      color: Colors.red.shade400,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMessageComposer() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(8.0),
      margin: EdgeInsets.only(
        left: 16.0,
        right: 16.0,
        bottom: _isChatting ? 8.0 : 32.0,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_isChatting ? 24.0 : 30.0),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _textController,
              decoration: InputDecoration(
                hintText:
                    _isChatting ? 'Type a message...' : 'Your reflection...',
                border: InputBorder.none,
              ),
              onSubmitted: _handleSubmitted,
              onTap: () {
                setState(() {
                  _isChatting = true; // Transition to chat layout
                });
              },
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            decoration: BoxDecoration(
              color: _isChatting ? Colors.blue : Colors.blue.shade50,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.send),
              color: _isChatting ? Colors.white : Colors.blue,
              onPressed: () => _handleSubmitted(_textController.text),
            ),
          ),
        ],
      ),
    );
  }

  // Move this method INSIDE the ChatScreenState class
  String _extractMoodFromResponse(String response) {
    // Make lowercase for case-insensitive matching
    final lowerResponse = response.toLowerCase();

    // Expanded map of mood keywords with more comprehensive indicators
    final Map<String, List<String>> moodKeywords = {
      'Happy': [
        'happy',
        'joy',
        'glad',
        'cheerful',
        'delighted',
        'pleased',
        'excited',
        'thrilled',
        'content',
        'satisfied',
        'elated',
        'wonderful',
        'great',
        'fantastic',
        'terrific',
        'good mood',
        'positive',
        'upbeat',
        'enthusiastic',
        'overjoyed',
        'ecstatic',
        'smiling',
        'laugh',
        'laughing',
        'grin',
        'beaming',
        'radiant',
        'uplifted'
      ],
      'Sad': [
        'sad',
        'unhappy',
        'depressed',
        'down',
        'blue',
        'gloomy',
        'miserable',
        'sorrow',
        'grief',
        'heartbroken',
        'devastated',
        'upset',
        'discouraged',
        'disappointed',
        'despondent',
        'disheartened',
        'distressed',
        'melancholy',
        'mournful',
        'hopeless',
        'forlorn',
        'tearful',
        'crying',
        'weeping',
        'somber',
        'dejected',
        'downcast',
        'bummed'
      ],
      'Angry': [
        'angry',
        'upset',
        'frustrated',
        'mad',
        'furious',
        'irritated',
        'annoyed',
        'agitated',
        'outraged',
        'resentful',
        'hostile',
        'enraged',
        'incensed',
        'indignant',
        'livid',
        'provoked',
        'irate',
        'fuming',
        'seething',
        'vexed',
        'infuriated',
        'cross',
        'grumpy'
      ],
      'Calm': [
        'calm',
        'relaxed',
        'peaceful',
        'tranquil',
        'serene',
        'composed',
        'collected',
        'centered',
        'at ease',
        'mellow',
        'soothing',
        'quiet',
        'settled',
        'still',
        'placid',
        'unruffled',
        'zen',
        'harmonious',
        'balanced',
        'restful',
        'chill',
        'stable',
        'steady',
        'level-headed'
      ],
      'Anxious': [
        'anxious',
        'worried',
        'nervous',
        'stress',
        'tense',
        'uneasy',
        'apprehensive',
        'concerned',
        'afraid',
        'fearful',
        'scared',
        'frightened',
        'alarmed',
        'panicky',
        'jittery',
        'edgy',
        'restless',
        'troubled',
        'bothered',
        'distressed',
        'fretful',
        'agitated',
        'overwhelmed',
        'dreading',
        'panic',
        'terror',
        'phobia',
        'dread',
        'uncertainty',
        'doubt',
        'hesitant'
      ],
      'Neutral': [
        'neutral',
        'fine',
        'okay',
        'alright',
        'average',
        'moderate',
        'so-so',
        'fair',
        'indifferent',
        'impartial',
        'balanced',
        'medium',
        'standard',
        'usual',
        'regular'
      ]
    };

    // Contextual tone analysis with weights
    Map<String, int> moodScores = {
      'Happy': 0,
      'Sad': 0,
      'Angry': 0,
      'Calm': 0,
      'Anxious': 0,
      'Neutral': 0,
    };

    // Check for exact keyword matches
    for (final entry in moodKeywords.entries) {
      for (final keyword in entry.value) {
        if (lowerResponse.contains(keyword)) {
          // Increase score for this mood
          moodScores[entry.key] = moodScores[entry.key]! + 2;
          print("Found mood keyword: $keyword, adding to ${entry.key} score");
        }
      }
    }

    // Look for sentence sentiment indicators
    if (lowerResponse.contains('feeling better') ||
        lowerResponse.contains('that\'s great') ||
        lowerResponse.contains('good to hear')) {
      moodScores['Happy'] = moodScores['Happy']! + 1;
    }

    if (lowerResponse.contains('sorry to hear') ||
        lowerResponse.contains('that sounds difficult') ||
        lowerResponse.contains('that must be hard')) {
      moodScores['Sad'] = moodScores['Sad']! + 1;
    }

    if (lowerResponse.contains('take a deep breath') ||
        lowerResponse.contains('relax') ||
        lowerResponse.contains('let\'s focus')) {
      moodScores['Calm'] = moodScores['Calm']! + 1;
    }

    if (lowerResponse.contains('it\'s understandable') ||
        lowerResponse.contains('many people feel this way') ||
        lowerResponse.contains('it\'s common to')) {
      moodScores['Neutral'] = moodScores['Neutral']! + 1;
    }

    // If clear patterns like "you seem" or "you sound" are present
    if (lowerResponse.contains('you seem happy') ||
        lowerResponse.contains('you sound cheerful')) {
      moodScores['Happy'] = moodScores['Happy']! + 3;
    }
    if (lowerResponse.contains('you seem sad') ||
        lowerResponse.contains('you sound down')) {
      moodScores['Sad'] = moodScores['Sad']! + 3;
    }
    if (lowerResponse.contains('you seem angry') ||
        lowerResponse.contains('you sound frustrated')) {
      moodScores['Angry'] = moodScores['Angry']! + 3;
    }
    if (lowerResponse.contains('you seem calm') ||
        lowerResponse.contains('you sound relaxed')) {
      moodScores['Calm'] = moodScores['Calm']! + 3;
    }
    if (lowerResponse.contains('you seem anxious') ||
        lowerResponse.contains('you sound worried')) {
      moodScores['Anxious'] = moodScores['Anxious']! + 3;
    }

    // Debug output
    print("Mood scores: $moodScores");

    // Find the mood with the highest score
    String detectedMood = '';
    int highestScore = 0;

    moodScores.forEach((mood, score) {
      if (score > highestScore) {
        highestScore = score;
        detectedMood = mood;
      }
    });

    // Only return a mood if the score is above a threshold (to avoid false positives)
    if (highestScore > 1) {
      print("Detected mood: $detectedMood with score $highestScore");
      return detectedMood;
    }

    // If no strong mood was detected
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

  // Update the _buildMoodOption method
  Widget _buildMoodOption(String mood, String emoji) {
    return SimpleDialogOption(
      onPressed: () {
        Navigator.pop(context);
        _updateMood(mood); // Use the new method
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

  Widget _buildGreetingSection() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            "Hello, what can I do for you today?",
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 10),
          Text(
            "Share your thoughts and feelings below",
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  void _showCrisisAlert(
      BuildContext context, String crisisType, String resources) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.red),
            const SizedBox(width: 8),
            const Text('Important Information',
                style: TextStyle(color: Colors.red)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Based on your message, you may need support.',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(resources),
            ],
          ),
        ),
        actions: [
          TextButton(
            child: const Text('I understand'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Get Help Now',
                style: TextStyle(color: Colors.white)),
            onPressed: () async {
              Navigator.of(context).pop();

              // Use the safer showDialog approach instead of direct URL launching
              final phoneNumber =
                  '1-800-273-8255'; // National Suicide Prevention Lifeline

              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Call for Help'),
                  content: Text(
                      'Would you like to call $phoneNumber for immediate assistance?'),
                  actions: [
                    TextButton(
                      child: const Text('Cancel'),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    TextButton(
                      child: const Text('Call',
                          style: TextStyle(
                              color: Colors.red, fontWeight: FontWeight.bold)),
                      onPressed: () {
                        Navigator.of(context).pop();
                        _showCrisisResourcesDetails();
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showCrisisResourcesDetails() {
    if (_currentCrisisInfo == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Crisis Resources'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Type: ${_currentCrisisInfo!['type']}'),
              const SizedBox(height: 12),
              Text(_currentCrisisInfo!['resources']),
            ],
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Close'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  // Add this method to your ChatScreenState class
  void _debugMoodState() {
    print("Current mood state: $_currentMood");

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Current mood: ${_currentMood ?? 'Not set'}'),
        action: SnackBarAction(
          label: 'Change',
          onPressed: _showMoodSelectionDialog,
        ),
      ),
    );
  }

  // Add this method to your ChatScreenState class
  void _updateMood(String newMood) {
    // Only update if it's actually different
    if (newMood.isNotEmpty && newMood != _currentMood) {
      setState(() {
        _currentMood = newMood;
        print("Mood updated to: $_currentMood");
      });

      // Extra step to ensure UI updates
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) setState(() {});
      });

      // Show a subtle indicator when mood changes automatically
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Mood updated to: $newMood'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 70.0, left: 20, right: 20),
        ),
      );
    }
  }
}

// Add this class at the top level of your file (outside any other classes)
class CustomFloatingActionButtonLocation extends FloatingActionButtonLocation {
  final double offsetY;

  const CustomFloatingActionButtonLocation(this.offsetY);

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry scaffoldGeometry) {
    // Get the default position from endFloat
    final Offset offset =
        FloatingActionButtonLocation.endFloat.getOffset(scaffoldGeometry);

    // Return a new position with adjusted Y
    return Offset(offset.dx, offset.dy - offsetY);
  }
}
