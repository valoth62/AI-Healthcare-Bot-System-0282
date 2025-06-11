import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'chat_screen.dart';
import 'package:http/http.dart' as http;

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Position? _currentLocation;

  @override
  void initState() {
    super.initState();
    _checkLocationPermission();
  }

  Future<void> _checkLocationPermission() async {
    final locationPermission = await Permission.locationWhenInUse.status;
    if (locationPermission == PermissionStatus.granted) {
      await _getCurrentLocation();
    } else {
      print('Location permission denied or not requested');
    }
  }

  Future<void> _requestPermissionAndFetchLocation() async {
    final locationPermission = await Permission.locationWhenInUse.request();
    if (locationPermission == PermissionStatus.granted) {
      await _getCurrentLocation();
    } else {
      print('Location permission denied');
      // Navigate to ChatScreen even if permission is denied
      _navigateToChatScreen();
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      final locationData = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _currentLocation = locationData;
      });
     // await _sendLocationToBackend(locationData);
      // Navigate to ChatScreen after location is fetched and sent
      _navigateToChatScreen();
    } catch (e) {
      print('Error getting location: $e');
      // Navigate to ChatScreen even if there's an error getting the location
      _navigateToChatScreen();
    }
  }

/*  Future<void> _sendLocationToBackend(Position position) async {
    final url = Uri.parse('http://192.168.1.19:5000/location');
    try {
      final response = await http.post(
        url,
        body: {
          'latitude': position.latitude.toString(),
          'longitude': position.longitude.toString(),
        },
      );
      if (response.statusCode == 200) {
        print('Location sent successfully');
      } else {
        print('Failed to send location');
      }
    } catch (e) {
      print('Error sending location: $e');
    }
  }*/

  void _navigateToChatScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => MyChatApp()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue[100]!, Colors.blue[600]!],
          ),
        ),
        child:Center(child:Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/logo.png',
              width: 100.0,
              height: 100.0,
            ),
            SizedBox(height: 20.0),
            Text(
              'E-BOT',
              style: TextStyle(fontSize: 24.0,fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20.0),
            ElevatedButton(
              onPressed: () async {
                await _requestPermissionAndFetchLocation();
              },
              child: Text('Start Chat',style:TextStyle(fontWeight: FontWeight.bold,color: Colors.white),),
              style: ElevatedButton.styleFrom(
                backgroundColor: Color.fromARGB(255, 0, 51, 77),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10.0),
                ),
              ),
            ),
          ],
        ),),
      ),
    );
  }
}
