import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class Esp32Service extends ChangeNotifier {
  String _ipAddress = "192.168.4.1";
  bool _isConnected = false;
  bool _isLoading = false;
  final List<String> _logs = [];
  List<String> _images = [];
  Uint8List? _previewImage;

  String get ipAddress => _ipAddress;
  bool get isConnected => _isConnected;
  bool get isLoading => _isLoading;
  List<String> get logs => List.unmodifiable(_logs);
  List<String> get images => _images;
  Uint8List? get previewImage => _previewImage;

  void setIpAddress(String ip) {
    _ipAddress = ip;
    addLog("Target IP set to: $ip");
    notifyListeners();
  }

  void addLog(String message) {
    String timestamp = DateTime.now().toIso8601String().split('T').last.split('.').first;
    _logs.add("[$timestamp] $message");
    notifyListeners();
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  Future<void> connect() async {
    if (_ipAddress.isEmpty) {
      addLog("Error: IP Address is empty.");
      return;
    }

    addLog("Connecting to $_ipAddress...");
    _isConnected = false;
    notifyListeners();

    try {
      // Pinging /images as a health check
      final uri = Uri.parse('http://$_ipAddress/images'); 
      final response = await http.get(uri).timeout(const Duration(seconds: 25));

      if (response.statusCode >= 200 && response.statusCode < 400) {
         _isConnected = true;
         addLog("Connected! Device responded to /images");
         // Automatically fetch images upon successful connection
         fetchImages();
      } else {
         addLog("Device reachable but /images returned error: ${response.statusCode}");
         _isConnected = true; 
      }
    } catch (e) {
      _isConnected = false;
      addLog("Connection failed: $e");
    }
    notifyListeners();
  }

  Future<void> fetchImages() async {
    if (_ipAddress.isEmpty) return;

    _isLoading = true;
    notifyListeners();

    addLog("Fetching image list...");
    try {
      final response = await http.get(
        Uri.parse('http://$_ipAddress/images'),
      ).timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        _images = List<String>.from(jsonDecode(response.body));
        addLog("Found ${_images.length} images");
      } else {
        addLog("Failed to fetch images: ${response.statusCode}");
      }
    } catch (e) {
      addLog("Error fetching images: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadPreview(String imageName) async {
    addLog("Loading preview for $imageName...");
    try {
      final response = await http.get(
        Uri.parse('http://$_ipAddress/image?name=$imageName'),
      ).timeout(const Duration(seconds: 25));
      
      if (response.statusCode == 200) {
        _previewImage = response.bodyBytes;
        addLog("Preview loaded successfully");
        notifyListeners();
      } else {
        addLog("Failed to load preview: ${response.statusCode}");
      }
    } catch (e) {
      addLog("Preview error: $e");
    }
  }

  void clearImages() {
    _images = [];
    _previewImage = null;
    notifyListeners();
  }
}
