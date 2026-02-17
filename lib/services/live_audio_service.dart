import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:vosk_flutter/vosk_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

class LiveAudioService {
  WebSocketChannel? _channel;
  
  final StreamController<String> _textStreamController = StreamController<String>.broadcast();
  Stream<String> get textStream => _textStreamController.stream;

  final StreamController<bool> _connectedController = StreamController<bool>.broadcast();
  Stream<bool> get isConnectedStream => _connectedController.stream;

  VoskFlutterPlugin? _vosk;
  Model? _model;
  Recognizer? _recognizer;
  SpeechService? _speechService;
  bool _isModelLoaded = false;

  // Configuration
  // ESP32 Audio settings: usually 16000Hz or 8000Hz. Adjust if necessary.
  static const int sampleRate = 16000; 

  LiveAudioService() {
    _vosk = VoskFlutterPlugin.instance();
  }

  Future<void> init() async {
    if (_isModelLoaded) return;
    
    try {
        // Attempt to load model from assets/models/model
        // Ideally user has placed the model there and updated pubspec.yaml
        final modelPath = await ModelLoader().loadFromAssets('assets/models/model.zip');
        _model = await _vosk!.createModel(modelPath);
        _recognizer = await _vosk!.createRecognizer(
            model: _model!,
            sampleRate: sampleRate,
        );
        _isModelLoaded = true;
        print("Vosk model loaded successfully");
    } catch (e) {
        print("Error loading Vosk model: $e");
        _textStreamController.add("Create folder assets/models/model and place Vosk model there.");
    }
  }

  void connect(String ipAddress) {
    disconnect(); // Ensure clean slate
    stopMicrophone(); // Ensure mic is off
    
    // Default port 80 for ESP32 AsyncWebServer unless specified otherwise.
    // The endpoint is likely /ws or root, but usually /ws for clean separation.
    // Based on user code: asyncServer.addHandler(&ws);
    // If ws path is not set in constructor, default is usually /ws or need to check.
    // Assuming /ws as standard practice.
    final uri = Uri.parse('ws://$ipAddress/ws');
    print("Connecting to $uri");

    try {
      _channel = WebSocketChannel.connect(uri);
      _connectedController.add(true);

      // Handshake: Send PING
      // "When we open app ... verify that our device is connected"
      _channel!.sink.add("PING");

      _channel!.stream.listen(
        (message) {
          if (message is String) {
            print("Received text: $message");
            if (message == "PONG") {
              print("Handshake confirmed");
            }
          } else if (message is List<int>) {
            // Audio data
            _processAudio(Uint8List.fromList(message));
          }
        },
        onDone: () {
          print("WS Disconnected");
          _connectedController.add(false);
        },
        onError: (error) {
          print("WS Error: $error");
          _connectedController.add(false);
        },
      );
    } catch (e) {
      print("Connection exception: $e");
      _connectedController.add(false);
    }
  }

  Future<void> _processAudio(Uint8List data) async {
    if (!_isModelLoaded || _recognizer == null) return;

    // acceptWaveformBytes returns true if a complete result is ready
    if (await _recognizer!.acceptWaveformBytes(data)) {
        final result = await _recognizer!.getResult();
        // Result is JSON: {"text": "..."}
        try {
           final json = jsonDecode(result);
           final text = json['text'] as String?;
           if (text != null && text.isNotEmpty) {
             _textStreamController.add(text); // Final result
           }
        } catch (e) {
           // raw result
           _textStreamController.add(result);
        }
    } else {
        final partial = await _recognizer!.getPartialResult();
        // Partial is JSON: {"partial": "..."}
        try {
           final json = jsonDecode(partial);
           final text = json['partial'] as String?;
            if (text != null && text.isNotEmpty) {
             // We might want to stream partial results too, 
             // but UI handles them differently usually.
             // For now, let's stream everything and let UI decide.
             // Or prefix standard: "PARTIAL: hello"
             _textStreamController.add("PARTIAL: $text");
           }
        } catch (e) {
           // raw partial
        }
    }
  }

  void disconnect() {
    if (_channel != null) {
      try {
        _channel!.sink.close(status.goingAway);
      } catch (e) {
        // ignore
      }
      _channel = null;
    }
    _connectedController.add(false);
  }

  Future<void> startMicrophone() async {
    disconnect(); // Ensure WS is off
    if (!_isModelLoaded || _recognizer == null) {
      await init();
      if (!_isModelLoaded) {
          _textStreamController.add("Model not loaded yet.");
          return;
      }
    }
    
    // Stop any existing speech service
    await stopMicrophone();

    try {
      _speechService = await _vosk!.initSpeechService(_recognizer!);
      
      _speechService!.onPartial().listen((partial) {
          try {
             final json = jsonDecode(partial);
             final text = json['partial'] as String?;
              if (text != null && text.isNotEmpty) {
               _textStreamController.add("PARTIAL: $text");
             }
          } catch (e) {
             // ignore
          }
      });
      
      _speechService!.onResult().listen((result) {
          try {
             final json = jsonDecode(result);
             final text = json['text'] as String?;
             if (text != null && text.isNotEmpty) {
               _textStreamController.add(text); 
             }
          } catch (e) {
             // ignore
          }
      });
      
      await _speechService!.start();
      print("Microphone started");
    } catch (e) {
      print("Error starting microphone: $e");
      _textStreamController.add("Error starting mic: $e");
    }
  }

  Future<void> stopMicrophone() async {
     if (_speechService != null) {
      await _speechService!.stop();
      await _speechService!.dispose();
      _speechService = null;
      print("Microphone stopped");
    }
  }
  
  void dispose() {
    stopMicrophone(); // Ensure mic is stopped
    disconnect();
    _recognizer?.dispose();
    _model?.dispose();
    _textStreamController.close();
    _connectedController.close();
  }
}
