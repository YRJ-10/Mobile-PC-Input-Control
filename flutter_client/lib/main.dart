import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const MobilePCApp());
}

class MobilePCApp extends StatelessWidget {
  const MobilePCApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MobilePC',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.tealAccent,
        scaffoldBackgroundColor: const Color(0xFF0F111A),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0F111A),
          elevation: 0,
        ),
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

  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _lastRecognizedWords = "";

  static const platform = MethodChannel('com.mobilepcmedia/audio');

  // Tab State: 0 untuk Touchpad, 1 untuk Media
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _requestMicrophonePermission();
  }

  Future<void> _requestMicrophonePermission() async {
    var status = await Permission.microphone.status;
    if (!status.isGranted) {
      await Permission.microphone.request();
    }
  }

  @override
  void dispose() {
    _socket?.close();
    _ipController.dispose();
    _textController.dispose();
    _stopNativeAudioReceiver();
    super.dispose();
  }

  Future<void> _startNativeAudioReceiver() async {
    try {
      await platform.invokeMethod('startAudioReceiver');
    } on PlatformException catch (e) {
      debugPrint("Failed to start Native Audio: '${e.message}'.");
    }
  }

  Future<void> _stopNativeAudioReceiver() async {
    try {
      await platform.invokeMethod('stopAudioReceiver');
    } on PlatformException catch (e) {
      debugPrint("Failed to stop Native Audio: '${e.message}'.");
    }
  }

  void _connectToServer() async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) return;

    try {
      setState(() => _statusMessage = "Connecting...");
      _socket = await Socket.connect(ip, 8080, timeout: const Duration(seconds: 5));
      _socket!.setOption(SocketOption.tcpNoDelay, true);

      setState(() {
        _isConnected = true;
        _statusMessage = "Connected to $ip";
      });

      _startNativeAudioReceiver();

      _socket!.listen(
        (data) {},
        onError: (error) => _disconnect(),
        onDone: () => _disconnect(),
      );
    } catch (e) {
      setState(() => _statusMessage = "Connection failed: $e");
    }
  }

  void _disconnect() {
    _socket?.close();
    _stopNativeAudioReceiver();
    setState(() {
      _isConnected = false;
      _statusMessage = "Disconnected";
    });
  }

  void _confirmDisconnect() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Disconnect?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to disconnect from the PC?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent, 
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _disconnect();
            },
            child: const Text('Disconnect', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _sendCommand(Map<String, dynamic> command) {
    if (_isConnected && _socket != null) {
      final jsonStr = jsonEncode(command) + '\n';
      _socket!.write(jsonStr);
    }
  }

  // --- MOUSE CONTROLS ---
  double _accumulatedDx = 0;
  double _accumulatedDy = 0;
  DateTime _lastPanTime = DateTime.now();

  void _onPanUpdate(DragUpdateDetails details) {
    _accumulatedDx += details.delta.dx;
    _accumulatedDy += details.delta.dy;

    final now = DateTime.now();
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
      FocusScope.of(context).unfocus();
    }
  }

  // --- VOICE COMMAND ---
  void _startListening() async {
    if (!_isConnected) return;
    bool available = await _speech.initialize(
      onStatus: (val) {
        if (val == 'done' || val == 'notListening') {
          setState(() => _isListening = false);
        }
      },
      onError: (val) => debugPrint('onError: $val'),
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
    setState(() => _isListening = false);
  }

  InputDecoration _modernInputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.grey),
      filled: true,
      fillColor: const Color(0xFF1A1D2D),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.tealAccent, width: 1.5),
      ),
    );
  }

  // --- TAB 1: TOUCHPAD ---
  Widget _buildTouchpadTab() {
    return Column(
      key: const ValueKey('touchpad'),
      children: [
        Expanded(
          child: GestureDetector(
            onPanUpdate: _onPanUpdate,
            onTap: _onTap,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF131520),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.teal.withOpacity(0.15), width: 1),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.touch_app_rounded, color: Colors.white24, size: 48),
                    const SizedBox(height: 12),
                    const Text(
                      'TOUCHPAD',
                      style: TextStyle(color: Colors.white30, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 2),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Slide to move • Tap to click',
                      style: TextStyle(color: Colors.white24, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _sendCommand({"type": "MOUSE_CLICK", "button": "left"}),
                icon: const Icon(Icons.mouse, size: 18),
                label: const Text('Left Click'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: const Color(0xFF1A1D2D),
                  foregroundColor: Colors.tealAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  side: BorderSide(color: Colors.teal.withOpacity(0.3), width: 1),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _sendCommand({"type": "MOUSE_CLICK", "button": "right"}),
                icon: const Icon(Icons.mouse, size: 18),
                label: const Text('Right Click'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: const Color(0xFF1A1D2D),
                  foregroundColor: Colors.white70,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  side: const BorderSide(color: Colors.white24, width: 1),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // --- TAB 2: MEDIA & SCROLL ---
  Widget _buildMediaTab() {
    return Row(
      key: const ValueKey('media'),
      children: [
        // Kiri: Play/Pause Button
        Expanded(
          flex: 1,
          child: ElevatedButton.icon(
            onPressed: () => _sendCommand({"type": "MEDIA", "action": "playpause"}),
            icon: const Icon(Icons.play_circle_filled, size: 36),
            label: const Text('Play\nPause', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A1D2D),
              foregroundColor: Colors.tealAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              side: BorderSide(color: Colors.tealAccent.withOpacity(0.3), width: 1),
              elevation: 0,
            ),
          ),
        ),
        const SizedBox(width: 16),
        // Kanan: Giant Scroll Wheel
        Expanded(
          flex: 2,
          child: GestureDetector(
            onPanUpdate: (details) {
              final now = DateTime.now();
              if (now.difference(_lastPanTime).inMilliseconds >= 32) { // 30fps
                _sendCommand({
                  "type": "SCROLL",
                  "dy": details.delta.dy, // Kirim murni delta, biar server yang kalikan
                });
                _lastPanTime = now;
              }
            },
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF131520),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.teal.withOpacity(0.3), width: 2), // Border tegas
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.keyboard_double_arrow_up, color: Colors.white54, size: 40),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Center(
                      child: RotatedBox(
                        quarterTurns: 1,
                        child: Icon(Icons.linear_scale, color: Colors.tealAccent.withOpacity(0.7), size: 60),
                      ),
                    ),
                  ),
                  const Text('GIANT SCROLL', style: TextStyle(color: Colors.tealAccent, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 2)),
                  const SizedBox(height: 16),
                  const Icon(Icons.keyboard_double_arrow_down, color: Colors.white54, size: 40),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('MobilePC', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 20)),
        actions: [
          if (_isConnected) ...[
            const Icon(Icons.speaker_group, color: Colors.tealAccent, size: 20),
            const SizedBox(width: 6),
            const Center(child: Text('Audio ON', style: TextStyle(color: Colors.tealAccent, fontSize: 13, fontWeight: FontWeight.bold))),
            const SizedBox(width: 16),
          ],
          Icon(_isConnected ? Icons.wifi : Icons.wifi_off, 
              color: _isConnected ? Colors.greenAccent : Colors.redAccent, size: 24),
          const SizedBox(width: 16),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Column(
            children: [
              // 1. Area IP Connect
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ipController,
                      decoration: _modernInputDecoration('PC IP Address (e.g. 192.168.1.9)'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isConnected ? _confirmDisconnect : _connectToServer,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isConnected ? const Color(0xFF2A1515) : Colors.teal.shade700,
                      foregroundColor: _isConnected ? Colors.redAccent : Colors.white,
                      side: BorderSide(color: _isConnected ? Colors.redAccent : Colors.tealAccent, width: 1),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                      elevation: 0,
                    ),
                    child: Text(
                      _isConnected ? 'Disconnect' : 'Connect',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(_statusMessage, style: TextStyle(color: _isConnected ? Colors.greenAccent : Colors.grey[500], fontSize: 12)),
              ),
              const SizedBox(height: 20),

              // 2. Area Type Text Manual
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      decoration: _modernInputDecoration('Type text to PC manually...'),
                      style: const TextStyle(color: Colors.white),
                      onSubmitted: (_) => _sendText(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.teal.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.send_rounded, color: Colors.tealAccent),
                      onPressed: _sendText,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 3. Voice Command Raksasa
              GestureDetector(
                onLongPressStart: (_) => _startListening(),
                onLongPressEnd: (_) => _stopListening(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 120,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: _isListening ? Colors.redAccent.withOpacity(0.9) : const Color(0xFF1A1D2D),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _isListening ? Colors.redAccent : Colors.teal.withOpacity(0.3), 
                      width: 1.5
                    ),
                    boxShadow: _isListening 
                      ? [BoxShadow(color: Colors.redAccent.withOpacity(0.4), blurRadius: 15, spreadRadius: 0)] 
                      : [],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.mic_rounded, size: 40, color: _isListening ? Colors.white : Colors.tealAccent),
                      const SizedBox(width: 12),
                      Text(
                        _isListening ? 'Listening... (Release to Stop)' : 'Hold for Voice Command',
                        style: TextStyle(
                          color: _isListening ? Colors.white : Colors.white70, 
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 4. Area Multi-Tab Tipis
              Expanded(
                child: Column(
                  children: [
                    // A. Header Tab Tipis
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF131520),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.teal.withOpacity(0.2)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: () => setState(() => _currentPage = 0),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                              decoration: BoxDecoration(
                                color: _currentPage == 0 ? Colors.teal.withOpacity(0.3) : Colors.transparent,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                'Touchpad',
                                style: TextStyle(
                                  color: _currentPage == 0 ? Colors.tealAccent : Colors.white54,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => setState(() => _currentPage = 1),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                              decoration: BoxDecoration(
                                color: _currentPage == 1 ? Colors.teal.withOpacity(0.3) : Colors.transparent,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                'Media & Scroll',
                                style: TextStyle(
                                  color: _currentPage == 1 ? Colors.tealAccent : Colors.white54,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // B. Konten Tab Aktif
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: _currentPage == 0 ? _buildTouchpadTab() : _buildMediaTab(),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
