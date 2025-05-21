import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:arkit_plugin/arkit_plugin.dart';
import 'package:vector_math/vector_math_64.dart' as vector_math;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(MaterialApp(home: MyApp()));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with SingleTickerProviderStateMixin {
  final bool printTransform = false; // Add this variable to control debugPrint
  final TextEditingController _ipAddressController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  late IO.Socket _socket; // Use IO.Socket type for socket
  String _message = 'Not Connected.';
  String _position = '0,0,0';
  String _rotationXYZ = '0,0,0';
  bool _isConnected = false;

  late final ARKitController arkitController;
  late final Ticker _ticker;

  Duration _previousTimestamp = Duration.zero;
  final Duration _frameInterval = const Duration(milliseconds: 33); // ~30 fps

  @override
  void initState() {
    super.initState();
    _ipAddressController.text = '10.0.0.26'; // Or any default IP
    _portController.text = '5555'; // Or any default port

    _ticker = createTicker((elapsed) {
      final delta = elapsed - _previousTimestamp;
      if (delta >= _frameInterval) {
        _previousTimestamp = elapsed;
        _update(); // Your 30 FPS function here
      }
    });

    _ticker.start();
  }

  @override
  void dispose() {
    arkitController.dispose();
    _disconnect(); // Ensure disconnection on dispose
    _ipAddressController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    debugPrint("debugging connect");
    try {
      setState(() {
        _message = 'Connecting...';
      });
      final ipAddress = _ipAddressController.text;
      final port = int.parse(_portController.text);

      // Check if the socket is already connected
      // if (_socket != null) {
      //   _socket.dispose();
      // }
      // Create a new socket connection
      _socket = IO.io(
        'http://$ipAddress:$port',
        IO.OptionBuilder()
            .setTransports(['websocket']) // Use WebSocket instead of polling
            .setReconnectionAttempts(5) // Optional: set reconnection attempts
            .setReconnectionDelay(
              1000,
            ) // Optional: set delay between reconnections
            .setTimeout(5000) // Optional: set timeout for connection
            .disableAutoConnect() // Optional: manually control connect
            .build(),
      );

      _socket.onConnect((_) {
        print('Connected to server');
        setState(() {
          _isConnected = true;
          _message = 'Connected to: $ipAddress:$port';
        });
      });

      _socket.onConnectError((error) {
        print('Connection error: $error');
        setState(() {
          _isConnected = false;
          _message = 'Connection error: $error';
        });
      });

      _socket.connect(); // Manually trigger connection
    } catch (e) {
      setState(() {
        _isConnected = false;
        _message = 'Error connecting: $e';
      });
      _disconnect(); //clean up
    }
  }

  void _disconnect() {
    try {
      _socket.destroy();
    } catch (e) {
      if (printTransform) print('Error disconnecting: $e');
    } finally {
      setState(() {
        _isConnected = false;
        _message = 'Disconnected.';
      });
      // _timer?.cancel(); // Remove timer cancel
    }
  }

  Future<void> _update() async {
    // This function is called ~30 times per second
    if (printTransform) debugPrint('Tick at ${DateTime.now()}');
    if (arkitController != null) {
      // Perform ARKit updates here
      final camera_pos = await arkitController.cameraPosition();
      if (camera_pos == null) {
        if (printTransform) debugPrint('Camera position is null');
        return;
      } 
      if (printTransform) debugPrint('Camera position: $camera_pos');

      final camera_rot = await arkitController.getCameraEulerAngles();
      if (camera_rot == null) {
        if (printTransform) debugPrint('Camera rotation is null');
        return;
      }
      if (printTransform) debugPrint('Camera rotation: $camera_rot');

      
      // update the position and rotation strings with 3 decimal places
      setState(() {
      _position = '${camera_pos.x.toStringAsFixed(3)},'
          '${camera_pos.y.toStringAsFixed(3)},'
          '${camera_pos.z.toStringAsFixed(3)}';
      _rotationXYZ = '${camera_rot.x.toStringAsFixed(3)},'
          '${camera_rot.y.toStringAsFixed(3)},'
          '${camera_rot.z.toStringAsFixed(3)}';
    });
      // Convert rotation (Euler angles) to a rotation matrix
      final rotationMatrix =
          vector_math.Matrix4.identity()
            ..rotateX(camera_rot.x)
            ..rotateY(camera_rot.y)
            ..rotateZ(camera_rot.z);

      // Create a translation matrix from the camera position
      final translationMatrix = vector_math.Matrix4.translation(
        vector_math.Vector3(camera_pos.x, camera_pos.y, camera_pos.z),
      );

      // Combine rotation and translation into a transformation matrix
      final transformMatrix = translationMatrix * rotationMatrix;

      // Convert transformMatrix to JSON format
      final transformInfoJson = {
        'transformMatrix': [
          [
            transformMatrix[0],
            transformMatrix[1],
            transformMatrix[2],
            transformMatrix[3],
          ],
          [
            transformMatrix[4],
            transformMatrix[5],
            transformMatrix[6],
            transformMatrix[7],
          ],
          [
            transformMatrix[8],
            transformMatrix[9],
            transformMatrix[10],
            transformMatrix[11],
          ],
          [
            transformMatrix[12],
            transformMatrix[13],
            transformMatrix[14],
            transformMatrix[15],
          ],
        ],
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      if (printTransform)
        debugPrint('Transformation Matrix JSON: $transformInfoJson');
      // Send the transformation matrix to the server
      if (_isConnected) {
        _socket.emit('update', jsonEncode(transformInfoJson));
        if (printTransform) debugPrint('Sent transformation matrix to server');
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('TeleTool2')),
    body: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _ipAddressController,
              decoration: const InputDecoration(labelText: 'IP Address'),
            ),
            TextField(
              controller: _portController,
              decoration: const InputDecoration(labelText: 'Port'),
              keyboardType: TextInputType.number,
            ),
            ElevatedButton(
              onPressed: _isConnected ? _disconnect : _connect,
              child: Text(_isConnected ? 'Disconnect' : 'Connect'),
            ),
            Text(_message, style: const TextStyle(fontSize: 10)),
            SizedBox(
              width: 200, // Set the desired width
              height: 300, // Set the desired height
              child: ARKitSceneView(onARKitViewCreated: onARKitViewCreated),
            ),
            Text(
              'Position: $_position',
              style: const TextStyle(fontSize: 8),
            ),
            Text(
              'Rotation (XYZ): $_rotationXYZ',
              style: const TextStyle(fontSize: 8),
            ),
          ],
        ),
      ),
    ),
  );

  void onARKitViewCreated(ARKitController arkitController) {
    this.arkitController = arkitController;
    final node = ARKitNode(
      geometry: ARKitSphere(radius: 0.1),
      position: vector_math.Vector3(0, 0, -0.5),
    );
    this.arkitController.add(node);
  }
}
