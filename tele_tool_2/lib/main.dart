import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:arkit_plugin/arkit_plugin.dart';
import 'package:vector_math/vector_math_64.dart' as vector_math;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(MaterialApp(home: MyApp()));
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with SingleTickerProviderStateMixin {
  final bool isDebug = true; // Add this variable to control debugPrint
  final TextEditingController _ipAddressController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  Socket? _socket;
  String _message = 'Not Connected.';
  bool _isConnected = false;

  late final ARKitController arkitController;
  late final Ticker _ticker;

  Duration _previousTimestamp = Duration.zero;
  final Duration _frameInterval = const Duration(milliseconds: 33); // ~30 fps

  @override
  void initState() {
    super.initState();
    _ipAddressController.text = '192.168.1.100'; // Or any default IP
    _portController.text = '12345'; // Or any default port

    _ticker = createTicker((elapsed) {
      final delta = elapsed - _previousTimestamp;
      if (delta >= _frameInterval) {
        _previousTimestamp = elapsed;
        _update(); // Your 30 FPS function here
      }
    });

    _ticker.start();
  }

  Future<void> _update() async {
    // This function is called ~30 times per second
    if (isDebug) debugPrint('Tick at ${DateTime.now()}');
    if (arkitController != null) {
      // Perform ARKit updates here
      final camera_pos = await arkitController.cameraPosition();
      if (camera_pos == null) {
        if (isDebug) debugPrint('Camera position is null');
        return;
      }
      if (isDebug) debugPrint('Camera position: $camera_pos');

      final camera_rot = await arkitController.getCameraEulerAngles();
      if (camera_rot == null) {
        if (isDebug) debugPrint('Camera rotation is null');
        return;
      }
      if (isDebug) debugPrint('Camera rotation: $camera_rot');
    }
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
    try {
      setState(() {
        _message = 'Connecting...';
      });
      final ipAddress = _ipAddressController.text;
      final port = int.parse(_portController.text);
      _socket = await Socket.connect(
        ipAddress,
        port,
        timeout: const Duration(seconds: 5),
      ); //add timeout
      setState(() {
        _isConnected = true;
        _message = 'Connected to: ${ipAddress}:${port}';
      });
      // Start sending immediately after connect
      if (_isConnected && _socket != null) {
        _socket?.add(
          utf8.encode('hello\n'),
        ); // Add newline for server to recognize end of message.
        _socket?.flush(); // Ensure data is sent
      }
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
      _socket?.close();
    } catch (e) {
      if (isDebug) print('Error disconnecting: $e');
    } finally {
      _socket = null;
      setState(() {
        _isConnected = false;
        _message = 'Disconnected.';
      });
      // _timer?.cancel(); // Remove timer cancel
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ARKit in Flutter')),
    body: Center(
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
          Text(_message),
          SizedBox(
            width: 300, // Set the desired width
            height: 400, // Set the desired height
            child: ARKitSceneView(onARKitViewCreated: onARKitViewCreated),
          ),
        ],
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
