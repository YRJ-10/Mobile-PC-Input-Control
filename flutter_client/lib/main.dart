import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:sound_stream/sound_stream.dart';

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

  // Speech to Text
  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _lastRecognizedWords = "";

  // Audio Streaming Player
  final PlayerStream _player = PlayerStream();
  RawDatagramSocket? _udpSocket;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _requestMicrophonePermission();
    _initAudioPlayer();
  }

  Future<void> _requestMicrophonePermission() async {
    var status = await Permission.microphone.status;
    if (!status.isGranted) {
      await Permission.microphone.request();
    }
  }

  void _initAudioPlayer() async {
    try {
      // Inisialisasi pemutar PCM stream bawaan
      await _player.initialize();
      await _player.start();

      // Mulai UDP Listener di port 8081 untuk menerima paket audio dari PC
      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 8081);
      _udpSocket!.listen((RawSocketEvent e) {
        Datagram? d = _udpSocket!.receive();
        if (d != null) {
          // data PCM 16-bit 16000Hz dituliskan ke dalam player stream
          _player.writeChunk(d.data);
        }
      });
    } catch (e) {
      print("Error inisialisasi audio player: $e");
    }
  }

  @override
  void dispose() {
    _socket?.close();
    _udpSocket?.close();
    _player.stop();
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
      
      // MENGHILANGKAN DELAY: Matikan Nagle's Algorithm agar perintah langsung dikirim
      _socket!.setOption(SocketOption.tcpNoDelay, true);

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

  // Variabel untuk menampung pergerakan agar tidak spam
  double _accumulatedDx = 0;
  double _accumulatedDy = 0;
  DateTime _lastPanTime = DateTime.now();

  // --- MOUSE CONTROLS ---
  void _onPanUpdate(DragUpdateDetails details) {
    _accumulatedDx += details.delta.dx;
    _accumulatedDy += details.delta.dy;

    final now = DateTime.now();
    // THROTTLING: Hanya kirim data 60 kali per detik (setiap ~16ms)
    if (now.difference(_lastPanTime).inMilliseconds >= 16) {
      const double sensitivity = 2.5; 
      _sendCommand({
        "type": "MOUSE_MOVE",
        "dx": _accumulatedDx * sensitivity,
        "dy": _accumulatedDy * sensitivity,
      });
      
      _lastPanTime = now;
      _accumulatedDx = 0;
      _accumulatedDy = 0;
    }
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

  // --- VOICE COMMAND (Real-time Typing) ---
  void _startListening() async {
    if (!_isConnected) return;
    
    bool available = await _speech.initialize(
      onStatus: (val) {
        if (val == 'done' || val == 'notListening') {
          setState(() => _isListening = false);
        }
      },
      onError: (val) => print('onError: $val'),
    );

    if (available) {
      setState(() {
        _isListening = true;
        _lastRecognizedWords = ""; 
      });
      _speech.listen(
        onResult: (val) {
          String recognizedWords = val.recognizedWords;
          
          if (recognizedWords.startsWith(_lastRecognizedWords)) {
            String newWords = recognizedWords.substring(_lastRecognizedWords.length);
            if (newWords.isNotEmpty) {
              _sendCommand({"type": "TYPE_TEXT", "text": newWords});
            }
          }
          
          _lastRecognizedWords = recognizedWords;
        },
        listenMode: stt.ListenMode.dictation,
      );
    }
  }

  void _stopListening() {
    _speech.stop();
    setState(() {
      _isListening = false;
    });
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

            // Voice Command Button
            GestureDetector(
              onLongPressStart: (_) => _startListening(),
              onLongPressEnd: (_) => _stopListening(),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 100,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: _isListening ? Colors.redAccent : Colors.teal.shade800,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: _isListening 
                    ? [BoxShadow(color: Colors.redAccent.withOpacity(0.6), blurRadius: 20, spreadRadius: 5)] 
                    : [],
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.mic, size: 40, color: Colors.white),
                      Text(
                        _isListening ? 'Mendengarkan... (Lepas untuk stop)' : 'Tahan untuk Voice Command',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Text Input Area
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: const InputDecoration(
                      labelText: 'Type manually',
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
