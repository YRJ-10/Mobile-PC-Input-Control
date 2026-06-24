import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ScreenMirrorPage extends StatefulWidget {
  final String serverIp;
  final Function(Map<String, dynamic>) sendCommand;

  const ScreenMirrorPage({Key? key, required this.serverIp, required this.sendCommand}) : super(key: key);

  @override
  _ScreenMirrorPageState createState() => _ScreenMirrorPageState();
}

class _ScreenMirrorPageState extends State<ScreenMirrorPage> {
  Socket? _socket;
  Uint8List? _currentFrame;

  DateTime _lastMoveTime = DateTime.now();
  final Set<int> _activePointers = {};

  @override
  void initState() {
    super.initState();
    // Force landscape
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeLeft,
    ]);
    _connectToStream();
  }

  @override
  void dispose() {
    _socket?.destroy();
    // Revert to portrait
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  void _connectToStream() async {
    try {
      _socket = await Socket.connect(widget.serverIp, 8082, timeout: const Duration(seconds: 3));
      
      int expectedLength = -1;
      BytesBuilder buffer = BytesBuilder();

      _socket!.listen((Uint8List data) {
        buffer.add(data);
        
        while (true) {
          if (expectedLength == -1) {
            if (buffer.length >= 4) {
              final bytes = buffer.takeBytes();
              final ByteData byteData = ByteData.sublistView(Uint8List.fromList(bytes.sublist(0, 4)));
              expectedLength = byteData.getUint32(0, Endian.big);
              buffer.add(bytes.sublist(4));
            } else {
              break;
            }
          }
          
          if (expectedLength != -1 && buffer.length >= expectedLength) {
            final bytes = buffer.takeBytes();
            final frameData = Uint8List.fromList(bytes.sublist(0, expectedLength));
            
            if (mounted) {
              setState(() {
                _currentFrame = frameData;
              });
            }
            
            buffer.add(bytes.sublist(expectedLength));
            expectedLength = -1;
          } else {
            break;
          }
        }
      }, onDone: () {
        // Socket closed
      }, onError: (e) {
        // Socket error
      });
    } catch (e) {
      // Connection failed
    }
  }


  // ---------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: _currentFrame != null
                ? AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Builder(
                      builder: (context) {
                        return InteractiveViewer(
                          panEnabled: false, // Matikan 1-finger pan
                          minScale: 1.0,
                          maxScale: 5.0,
                          child: Listener(
                            onPointerDown: (e) {
                              _activePointers.add(e.pointer);
                              if (_activePointers.length == 1) {
                                final size = context.size;
                                if (size != null) {
                                  widget.sendCommand({
                                    "type": "TOUCH_DOWN",
                                    "rx": e.localPosition.dx / size.width,
                                    "ry": e.localPosition.dy / size.height,
                                  });
                                }
                              } else if (_activePointers.length == 2) {
                                widget.sendCommand({"type": "TOUCH_UP"});
                              }
                            },
                            onPointerMove: (e) {
                              if (_activePointers.length == 1) {
                                final size = context.size;
                                if (size != null) {
                                  final now = DateTime.now();
                                  if (now.difference(_lastMoveTime).inMilliseconds >= 16) {
                                    widget.sendCommand({
                                      "type": "TOUCH_MOVE",
                                      "rx": e.localPosition.dx / size.width,
                                      "ry": e.localPosition.dy / size.height,
                                    });
                                    _lastMoveTime = now;
                                  }
                                }
                              }
                            },
                            onPointerUp: (e) {
                              _activePointers.remove(e.pointer);
                              if (_activePointers.isEmpty) {
                                widget.sendCommand({"type": "TOUCH_UP"});
                              }
                            },
                            onPointerCancel: (e) {
                              _activePointers.remove(e.pointer);
                              if (_activePointers.isEmpty) {
                                widget.sendCommand({"type": "TOUCH_UP"});
                              }
                            },
                            child: Container(
                              color: Colors.black, // background color
                              width: double.infinity,
                              height: double.infinity,
                              child: Image.memory(
                                _currentFrame!,
                                gaplessPlayback: true,
                                fit: BoxFit.fill,
                              ),
                            ),
                          ),
                        );
                      }
                    ),
                  )
                : const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: Colors.redAccent),
                      SizedBox(height: 16),
                      Text("Connecting to Video Stream...", style: TextStyle(color: Colors.white70)),
                    ],
                  ),
          ),
          
          // Back button
          Positioned(
            top: 20,
            left: 20,
            child: SafeArea(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
