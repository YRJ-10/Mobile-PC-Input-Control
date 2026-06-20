import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

void main() {
  runApp(const MobilePCMediaApp());
}

class MobilePCMediaApp extends StatelessWidget {
  const MobilePCMediaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PC Remote Control',
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.teal,
        scaffoldBackgroundColor: const Color(0xFF1E1E2C),
      ),
      home: const RemoteHomePage(),
    );
  }
}

class RemoteHomePage extends StatefulWidget {
  const RemoteHomePage({super.key});

  @override
  State<RemoteHomePage> createState() => _RemoteHomePageState();
}

class _RemoteHomePageState extends State<RemoteHomePage> {
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _textController = TextEditingController();
  
  Socket? _socket;
  bool _isConnected = false;
  String _statusMessage = "Disconnected";

  @override
  void dispose() {
    _socket?.close();
    _ipController.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _connectToServer() async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) return;

    try {
      setState(() => _statusMessage = "Connecting...");
      _socket = await Socket.connect(ip, 8080, timeout: const Duration(seconds: 5));
      setState(() {
        _isConnected = true;
        _statusMessage = "Connected to $ip";
      });

      _socket!.listen(
        (data) {},
        onError: (error) {
          _disconnect();
        },
        onDone: () {
          _disconnect();
        },
      );
    } catch (e) {
      setState(() => _statusMessage = "Connection failed: $e");
    }
  }

  void _disconnect() {
    _socket?.close();
    setState(() {
      _isConnected = false;
      _statusMessage = "Disconnected";
    });
  }

  void _sendCommand(Map<String, dynamic> command) {
    if (_isConnected && _socket != null) {
      final jsonStr = jsonEncode(command) + '\n';
      _socket!.write(jsonStr);
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    // details.delta gives us the dx and dy of the movement
    _sendCommand({
      "type": "MOUSE_MOVE",
      "dx": details.delta.dx,
      "dy": details.delta.dy,
    });
  }

  void _onTap() {
    _sendCommand({"type": "MOUSE_CLICK", "button": "left"});
  }

  void _sendText() {
    final text = _textController.text;
    if (text.isNotEmpty) {
      _sendCommand({"type": "TYPE_TEXT", "text": text});
      _textController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PC Media & Remote'),
        actions: [
          Icon(_isConnected ? Icons.wifi : Icons.wifi_off, 
              color: _isConnected ? Colors.green : Colors.red),
          const SizedBox(width: 16),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Connection Area
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ipController,
                    decoration: const InputDecoration(
                      labelText: 'PC IP Address',
                      hintText: 'e.g., 192.168.1.15',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _isConnected ? _disconnect : _connectToServer,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isConnected ? Colors.red : Colors.teal,
                    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
                  ),
                  child: Text(_isConnected ? 'Disconnect' : 'Connect'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(_statusMessage, style: TextStyle(color: Colors.grey[400])),
            const Divider(height: 30),

            // Text Input Area
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: const InputDecoration(
                      labelText: 'Type to PC',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _sendText(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.teal),
                  onPressed: _sendText,
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Touchpad Area
            Expanded(
              child: GestureDetector(
                onPanUpdate: _onPanUpdate,
                onTap: _onTap,
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.teal.withOpacity(0.5)),
                  ),
                  child: const Center(
                    child: Text(
                      'TOUCHPAD\n(Slide to move, Tap to left click)',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, fontSize: 18),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Click Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () => _sendCommand({"type": "MOUSE_CLICK", "button": "left"}),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(120, 60),
                    backgroundColor: Colors.teal.shade700,
                  ),
                  child: const Text('Left Click'),
                ),
                ElevatedButton(
                  onPressed: () => _sendCommand({"type": "MOUSE_CLICK", "button": "right"}),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(120, 60),
                    backgroundColor: Colors.blueGrey.shade700,
                  ),
                  child: const Text('Right Click'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
