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
  bool _isScanning = false;

  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _lastRecognizedWords = "";

  static const platform = MethodChannel('com.mobilepcmedia/audio');
  bool _isAudioEnabled = true;

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

  // --- UDP DISCOVERY ---
  void _scanNetwork() async {
    setState(() => _isScanning = true);
    try {
      final udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      udpSocket.broadcastEnabled = true;
      
      // Listen for response
      udpSocket.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          Datagram? dg = udpSocket.receive();
          if (dg != null) {
            final message = utf8.decode(dg.data);
            if (message == "MOBILEPC_SERVER") {
              udpSocket.close();
              if (mounted) {
                setState(() {
                  _ipController.text = dg.address.address;
                  _isScanning = false;
                });
                _connectToServer();
              }
            }
          }
        }
      });

      // Broadcast to 255.255.255.255
      udpSocket.send(utf8.encode("DISCOVER_MOBILEPC"), InternetAddress("255.255.255.255"), 8081);
      
      // Timeout after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        if (_isScanning && mounted) {
          udpSocket.close();
          setState(() => _isScanning = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PC not found. Make sure PC server is running.', style: TextStyle(color: Colors.white))),
          );
        }
      });
    } catch (e) {
      if (mounted) setState(() => _isScanning = false);
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
        _isAudioEnabled = true;
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

  void _toggleAudio() {
    setState(() {
      _isAudioEnabled = !_isAudioEnabled;
    });
    
    // Kirim perintah ke server Python
    _sendCommand({
      "type": "AUDIO_TOGGLE",
      "enabled": _isAudioEnabled,
    });
    
    // Hidupkan/matikan receiver di Android native
    if (_isAudioEnabled) {
      _startNativeAudioReceiver();
    } else {
      _stopNativeAudioReceiver();
    }
  }

  // --- MOUSE & GESTURE CONTROLS ---
  double _accumulatedDx = 0;
  double _accumulatedDy = 0;
  DateTime _lastPanTime = DateTime.now();
  double _lastScale = 1.0;

  void _onScaleStart(ScaleStartDetails details) {
    _lastScale = 1.0;
  }

  void _onScaleUpdate(ScaleUpdateDetails details, BoxConstraints constraints) {
    // Deteksi Pinch to Zoom jika scale berubah signifikan dari 1.0
    if ((details.scale - 1.0).abs() > 0.05) {
      final now = DateTime.now();
      if (now.difference(_lastPanTime).inMilliseconds >= 64) {
        double scaleDelta = details.scale - _lastScale;
        if (scaleDelta.abs() > 0.02) {
          _sendCommand({
            "type": "ZOOM",
            "delta": scaleDelta > 0 ? 1 : -1
          });
          _lastScale = details.scale;
          _lastPanTime = now;
        }
      }
    } else {
      // Single Finger Mode
      // Hidden Scroll Zone (25% di sisi kanan untuk ruang yang lebih lega)
      if (details.localFocalPoint.dx > constraints.maxWidth * 0.75) {
        final now = DateTime.now();
        if (now.difference(_lastPanTime).inMilliseconds >= 16) {
          _sendCommand({
            "type": "SCROLL",
            "dy": details.focalPointDelta.dy,
          });
          _lastPanTime = now;
        }
      } else {
        // Normal Mouse Move
        _accumulatedDx += details.focalPointDelta.dx;
        _accumulatedDy += details.focalPointDelta.dy;

        final now = DateTime.now();
        if (now.difference(_lastPanTime).inMilliseconds >= 16) {
          const double sensitivity = 4.0; // Sensitivitas dinaikkan agar jangkauan lebih jauh
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

  // Helper Widget untuk Special Keys
  Widget _specialKeyBtn(String label, String keyCmd) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ActionChip(
        label: Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1A1D2D),
        side: BorderSide(color: Colors.teal.withOpacity(0.3), width: 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        onPressed: () => _sendCommand({"type": "SPECIAL_KEY", "key": keyCmd}),
      ),
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
            GestureDetector(
              onTap: _toggleAudio,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: _isAudioEnabled ? Colors.teal.withOpacity(0.2) : Colors.redAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _isAudioEnabled ? Colors.tealAccent.withOpacity(0.5) : Colors.redAccent.withOpacity(0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isAudioEnabled ? Icons.speaker_group : Icons.volume_off,
                      color: _isAudioEnabled ? Colors.tealAccent : Colors.redAccent,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isAudioEnabled ? 'Audio ON' : 'Audio OFF',
                      style: TextStyle(
                        color: _isAudioEnabled ? Colors.tealAccent : Colors.redAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
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
              // 1. Area IP Connect & Auto-Discovery
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ipController,
                      decoration: _modernInputDecoration('PC IP Address (Auto-Scan)'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.teal.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: IconButton(
                      icon: _isScanning 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.tealAccent)) 
                        : const Icon(Icons.search_rounded, color: Colors.tealAccent),
                      onPressed: _isScanning ? null : _scanNetwork,
                      tooltip: 'Auto-Discover PC',
                    ),
                  ),
                  const SizedBox(width: 8),
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

              // 2. Area Type Text Manual & Special Keys
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
              const SizedBox(height: 12),
              
              // Special Keys Row
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _specialKeyBtn('Alt+Tab 🔀', 'alttab'),
                    _specialKeyBtn('Enter ↵', 'enter'),
                    _specialKeyBtn('Bksp ⌫', 'backspace'),
                    _specialKeyBtn('Win ❖', 'win'),
                    _specialKeyBtn('Copy', 'copy'),
                    _specialKeyBtn('Paste', 'paste'),
                  ],
                ),
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

              // 4. Area Touchpad (dengan Hidden Scroll Zone)
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return GestureDetector(
                      onScaleStart: _onScaleStart,
                      onScaleUpdate: (details) => _onScaleUpdate(details, constraints),
                      onTap: _onTap,
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFF131520),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.teal.withOpacity(0.15), width: 1),
                        ),
                        child: Stack(
                          children: [
                            // Konten Tengah
                            Center(
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
                            // Penanda visual halus untuk zona Scroll (25% paling kanan)
                            Positioned(
                              right: 0,
                              top: 0,
                              bottom: 0,
                              width: constraints.maxWidth * 0.25,
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border(
                                    left: BorderSide(color: Colors.white.withOpacity(0.05), width: 1),
                                  ),
                                  gradient: LinearGradient(
                                    colors: [Colors.transparent, Colors.white.withOpacity(0.02)],
                                  ),
                                ),
                                child: const Center(
                                  child: Icon(Icons.unfold_more, color: Colors.white10, size: 30),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                ),
              ),
              const SizedBox(height: 16),

              // 5. Click Buttons
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
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}
