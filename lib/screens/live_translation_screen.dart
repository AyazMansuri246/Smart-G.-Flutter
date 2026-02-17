import 'package:flutter/material.dart';
import '../services/live_audio_service.dart';
import 'package:permission_handler/permission_handler.dart';

class LiveTranslationScreen extends StatefulWidget {
  const LiveTranslationScreen({super.key});

  @override
  State<LiveTranslationScreen> createState() => _LiveTranslationScreenState();
}

class _LiveTranslationScreenState extends State<LiveTranslationScreen> {
  final LiveAudioService _audioService = LiveAudioService();
  final TextEditingController _ipController = TextEditingController(text: "192.168.4.1");
  String _transcription = "";
  String _partialTranscription = "";
  bool _isConnected = false;
  bool _isMicOn = false;
  bool _isInit = false;

  @override
  void initState() {
    super.initState();
    _initService();
  }

  Future<void> _initService() async {
    await _audioService.init();
    
    _audioService.isConnectedStream.listen((connected) {
      if (mounted) {
        setState(() {
          _isConnected = connected;
        });
      }
    });

    _audioService.textStream.listen((text) {
      if (mounted) {
        setState(() {
          if (text.startsWith("PARTIAL:")) {
            _partialTranscription = text.substring(8).trim();
          } else {
             // Append confirmed text
             if (_transcription.isNotEmpty) {
               _transcription += " ";
             }
             _transcription += text;
             _partialTranscription = ""; // Clear partial
          }
        });
      }
    });

    setState(() {
      _isInit = true;
    });
  }

  @override
  void dispose() {
    _audioService.dispose();
    _ipController.dispose();
    super.dispose();
  }

  void _toggleConnection() {
    if (_isConnected) {
      _audioService.disconnect();
    } else {
      if (_isMicOn) {
        _audioService.stopMicrophone();
        setState(() => _isMicOn = false);
      }
      _audioService.connect(_ipController.text);
    }
  }

  void _toggleMic() async {
    if (_isMicOn) {
      await _audioService.stopMicrophone();
      setState(() => _isMicOn = false);
    } else {
      if (_isConnected) {
        _audioService.disconnect();
      }
      
      var status = await Permission.microphone.request();
      if (status.isGranted) {
        await _audioService.startMicrophone();
        setState(() => _isMicOn = true);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Microphone permission required for debugging")),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Live Translation"),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.deepPurple.shade50, Colors.white],
          ),
        ),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Connection Card
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _ipController,
                            decoration: const InputDecoration(
                              labelText: "ESP32 IP Address",
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.wifi),
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton.icon(
                          onPressed: _toggleConnection,
                          icon: Icon(_isConnected ? Icons.stop : Icons.play_arrow),
                          label: Text(_isConnected ? "Stop" : "Connect"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isConnected ? Colors.redAccent : Colors.teal,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(
                          _isConnected ? Icons.check_circle : Icons.circle_outlined,
                          color: _isConnected ? Colors.green : Colors.grey,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isConnected 
                              ? "Status: Connected & Handshake OK" 
                              : "Status: Disconnected",
                          style: TextStyle(
                            color: _isConnected ? Colors.green[700] : Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 30),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Debug Mode", 
                              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[700])
                            ),
                            const Text(
                              "Test with phone microphone", 
                              style: TextStyle(fontSize: 12, color: Colors.grey)
                            ),
                          ],
                        ),
                        ElevatedButton.icon(
                          onPressed: _toggleMic,
                          icon: Icon(_isMicOn ? Icons.mic_off : Icons.mic),
                          label: Text(_isMicOn ? "Stop Mic" : "Test Mic"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isMicOn ? Colors.deepOrange : Colors.grey[200],
                            foregroundColor: _isMicOn ? Colors.white : Colors.black87,
                            elevation: 0,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Transcription Area
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Live Transcription",
                      style: TextStyle(
                        fontSize: 14, 
                        fontWeight: FontWeight.bold, 
                        color: Colors.grey[600],
                        letterSpacing: 1.0,
                      ),
                    ),
                    const Divider(),
                    Expanded(
                      child: SingleChildScrollView(
                        reverse: true, // Auto-scroll to bottom
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _transcription.isEmpty && _partialTranscription.isEmpty
                                  ? "Waiting for audio..." 
                                  : _transcription,
                              style: const TextStyle(
                                fontSize: 18, 
                                height: 1.5,
                                color: Colors.black87,
                              ),
                            ),
                            if (_partialTranscription.isNotEmpty)
                              Text(
                                " $_partialTranscription",
                                style: TextStyle(
                                  fontSize: 18, 
                                  height: 1.5,
                                  color: Colors.grey[500],
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
