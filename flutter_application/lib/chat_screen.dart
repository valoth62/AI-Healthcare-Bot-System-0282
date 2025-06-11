import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'E-BOT',
    home: MyChatApp(),
  ));
}

class MyChatApp extends StatefulWidget {
  const MyChatApp({Key? key}) : super(key: key);

  @override
  MyChatAppState createState() => MyChatAppState();
}

class MyChatAppState extends State<MyChatApp> {
  TextEditingController textEditingController = TextEditingController();
  List<Map<String, String>> messageList = [];
  ScrollController scrollController = ScrollController();
  Position? _currentLocation;
  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _text = '';

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _loadMessages();
  }

  Future<void> _requestMicrophonePermission() async {
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      // Handle the case when the user denies the permission.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Microphone permission is required for speech recognition.'),
        ),
      );
    }
  }

  Future<void> _checkMicrophonePermissionAndListen() async {
    final status = await Permission.microphone.status;
    if (status == PermissionStatus.granted) {
      await _listen();
    } else {
      await _requestMicrophonePermission();
      if (await Permission.microphone.isGranted) {
        await _listen();
      }
    }
  }

  Future<void> _listen() async {
    if (_isListening) {
      setState(() => _isListening = false);
      _speech.stop();
      return;
    }

    bool available = await _speech.initialize(
      onStatus: (val) {
        if (val == 'done') {
          setState(() => _isListening = false);
        }
      },
      onError: (val) => print('onError: $val'),
    );

    if (available) {
      setState(() => _isListening = true);
      _speech.listen(
        onResult: (val) => setState(() {
          _text = val.recognizedWords;
          textEditingController.text = _text;
        }),
      );
    }
  }

  Future<void> scrollAnimation() async {
    return await Future.delayed(
      const Duration(milliseconds: 100),
          () => scrollController.animateTo(
        scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.linear,
      ),
    );
  }

  Future<void> _requestPermissionAndFetchLocation() async {
    final locationPermission = await Permission.locationWhenInUse.request();
    if (locationPermission == PermissionStatus.granted) {
      await _getCurrentLocation();
    } else {
      print('Location permission denied');
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      final locationData = await Geolocator.getCurrentPosition();
      setState(() {
        _currentLocation = locationData;
      });
      await _openGoogleMaps(locationData);
    } on Exception catch (e) {
      print('Error getting location: $e');
    }
  }

  Future<void> _openGoogleMaps(Position position) async {
    final query = '${position.latitude},${position.longitude}';
    final url = 'https://www.google.com/maps/search/?api=1&query=hospitals+near+$query';
    final googleMapsScheme = 'comgooglemaps://?q=hospitals&center=${position.latitude},${position.longitude}';

    print('Attempting to launch URL: $url'); // Debug statement

    if (await canLaunch(googleMapsScheme)) {
      await launch(googleMapsScheme);
      print('Google Maps app launched successfully'); // Debug statement
    } else if (await canLaunch(url)) {
      await launch(url);
      print('URL launched successfully'); // Debug statement
    } else {
      print('Could not launch $url or $googleMapsScheme'); // Debug statement
    }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri launchUri = Uri(
      scheme: 'tel',
      path: phoneNumber,
    );
    await launchUrl(launchUri);
  }

  Future<void> _sendMessageToBackend(String message) async {
    if (message.trim().isEmpty) return;

    setState(() {
      messageList.add({'sender': 'user', 'message': message, 'timestamp': DateTime.now().toIso8601String()});
      textEditingController.clear();
    });

    try {
      final response = await http.post(
        Uri.parse('http://192.168.1.19:5005/webhooks/rest/webhook'), // Your Rasa server URL
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'sender': 'user', 'message': message}),
      );

      if (response.statusCode == 200) {
        final List<dynamic> responseData = json.decode(response.body);
        for (var responseMessage in responseData) {
          setState(() {
            messageList.add({
              'sender': 'bot',
              'message': responseMessage['text'] ?? '',
              'timestamp': DateTime.now().toIso8601String()
            });
          });
        }
      } else {
        setState(() {
          messageList.add({
            'sender': 'bot',
            'message': 'Error: Could not connect to the server',
            'timestamp': DateTime.now().toIso8601String()
          });
        });
      }
    } catch (e) {
      setState(() {
        messageList.add({
          'sender': 'bot',
          'message': 'Error: $e',
          'timestamp': DateTime.now().toIso8601String()
        });
      });
    }

    await scrollAnimation();
    _saveMessages();
  }

  void _handleSendMessage() async {
    final message = textEditingController.text;
    await _sendMessageToBackend(message);
  }

  Future<void> _saveMessages() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> messageData = messageList.map((message) {
      return jsonEncode(message);
    }).toList();
    await prefs.setStringList('messages', messageData);
  }

  Future<void> _loadMessages() async {
    final prefs = await SharedPreferences.getInstance();
    List<String>? messageData = prefs.getStringList('messages');
    if (messageData != null) {
      setState(() {
        messageList = messageData.map((message) {
          return Map<String, String>.from(jsonDecode(message));
        }).toList();
      });
      _filterOldMessages();
    }
  }

  void _filterOldMessages() {
    DateTime now = DateTime.now();
    setState(() {
      messageList.removeWhere((message) {
        DateTime timestamp = DateTime.parse(message['timestamp'] ?? '');
        return now.difference(timestamp).inDays > 2;
      });
    });
    _saveMessages();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromRGBO(202, 225, 247, 1),
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 0, 51, 77),
        leadingWidth: 50.0,
        titleSpacing: 8.0,
        leading: const Padding(
          padding: EdgeInsets.only(left: 8.0),
          child: CircleAvatar(
            backgroundImage: AssetImage('assets/logo.jpg'),
          ),
        ),
        title: const Text(
          'E-BOT',
          style: TextStyle(
            color: Colors.white, fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.phone, color: Colors.white,),
            onPressed: () {
              _makePhoneCall('911'); // Make a call to 911
            },
          ),
          const Padding(
            padding: EdgeInsets.only(right: 20.0, left: 20.0),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: messageList.length,
              itemBuilder: (context, index) {
                final message = messageList[index];
                final isUserMessage = message['sender'] == 'user';
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    color: isUserMessage ? Color.fromARGB(255, 0, 128, 21) : Color.fromARGB(255, 155, 188, 191),
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: Text(
                    message['message'] ?? '',
                    style: TextStyle(
                      color: isUserMessage ? Colors.white : Colors.black,
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            margin: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              shape: BoxShape.rectangle,
              color: const Color.fromARGB(255, 0, 51, 77),
              borderRadius: const BorderRadius.all(Radius.circular(15.0)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  margin: const EdgeInsets.only(
                    left: 8.0,
                    right: 8.0,
                    bottom: 12.0,
                  ),
                  child: Transform.rotate(
                    angle: 45,
                    child: GestureDetector(
                      onTap: () async {
                        await _requestPermissionAndFetchLocation();
                      },
                      child: const Icon(
                        Icons.map,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(
                    left: 8.0,
                    right: 8.0,
                    bottom: 12.0,
                  ),
                  child: GestureDetector(
                    onTap: () async {
                      await _checkMicrophonePermissionAndListen();
                    },
                    child: Icon(
                      _isListening ? Icons.mic_off : Icons.mic,
                      color: Colors.white,
                    ),
                  ),
                ),
                Expanded(
                  child: TextFormField(
                    controller: textEditingController,
                    cursorColor: Colors.white,
                    keyboardType: TextInputType.multiline,
                    minLines: 1,
                    maxLines: 6,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Type your message...',
                      hintStyle: TextStyle(color: Colors.grey),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(
                    left: 8.0,
                    right: 8.0,
                    bottom: 11.0,
                  ),
                  child: Transform.rotate(
                    angle: -3.14 / 5,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 5.0),
                      child: GestureDetector(
                        onTap: () {
                          _handleSendMessage(); // Call the async function to send the message
                        },
                        onLongPress: () {
                          setState(() {
                            messageList.add({
                              'sender': 'user',
                              'message': textEditingController.text,
                              'timestamp': DateTime.now().toIso8601String(),
                            });
                            textEditingController.clear();
                            scrollAnimation();
                            _saveMessages(); // Save messages to cache
                          });
                        },
                        child: const Icon(
                          Icons.send,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

}
