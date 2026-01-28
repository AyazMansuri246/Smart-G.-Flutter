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
  List<String> _videos = [];
  Uint8List? _previewImage;

  String get ipAddress => _ipAddress;
  bool get isConnected => _isConnected;
  bool get isLoading => _isLoading;
  List<String> get logs => List.unmodifiable(_logs);
  List<String> get images => _images;
  List<String> get videos => _videos;
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

  Future<void> fetchVideos() async {
    if (_ipAddress.isEmpty) return;
    
    // Explicit log as requested by user
    addLog("Requesting video list from ESP32...");
    
    _isLoading = true;
    notifyListeners();
    
    try {
      final response = await http.get(Uri.parse('http://$_ipAddress/videos')).timeout(const Duration(seconds: 25));
      if (response.statusCode == 200) {
        _videos = List<String>.from(jsonDecode(response.body));
        addLog("Found ${_videos.length} videos on SD Card");
      } else {
        addLog("Failed to fetch videos: ${response.statusCode}");
      }
    } catch (e) {
      addLog("Error fetching videos: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

/*
So why did it fail before?
Because earlier your app was likely sending:
video_025.avi

WITHOUT encoding and WITHOUT leading slash, and maybe even using the wrong endpoint like:
/download?name=video_025.avi   ❌
But now you're sending:
/video?file=%2Fvideo_025.avi  ✅
Which becomes internally:
/video_025.avi
Perfect SD path.
 */
// Very important!!!!!!.

  Future<Stream<List<int>>?> downloadVideoStream(String videoName) async {
    addLog("Starting download stream for $videoName...");
    try {
      // Ensure the name has a leading slash if the ESP32 expects it
      final fileName = videoName.startsWith('/') ? videoName : '/$videoName';
      final encoded = Uri.encodeComponent(fileName);
      
      // Use 'file' to match the ESP32 code: if (!req->hasParam("file")) ...
      final url = 'http://$_ipAddress/video?file=$encoded';
      addLog("Request URL: $url");

      final request = http.Request('GET', Uri.parse(url));
      final response = await request.send().timeout(const Duration(seconds: 60));
      
      addLog("Download response code: ${response.statusCode}");
      if (response.statusCode == 200) {
        return response.stream;
      } else if (response.statusCode == 503) {
        addLog("ESP32 busy: recording in progress.");
      } else {
        addLog("Failed to start download stream: ${response.statusCode}");
      }
    } catch (e) {
      addLog("Error initiating download stream: $e");
    }
    return null;
  }

  Future<Uint8List?> downloadVideo(String videoName) async {
    // Legacy method - prefer stream for large files
    addLog("Downloading $videoName (Legacy)...");
    try {
      final response = await http.get(Uri.parse('http://$_ipAddress/video?name=$videoName')).timeout(const Duration(seconds: 60));
      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        addLog("Failed to download $videoName: ${response.statusCode}");
      }
    } catch (e) {
      addLog("Error downloading video: $e");
    }
    return null;
  }

  Future<bool> deleteVideo(String videoName) async {
    addLog("Deleting video $videoName from ESP32...");
    try {
      final response = await http.get(Uri.parse('http://$_ipAddress/video/delete?name=$videoName')).timeout(const Duration(seconds: 25));
      if (response.statusCode == 200) {
        addLog("Video $videoName deleted from ESP32.");
        _videos.remove(videoName);
        notifyListeners();
        return true;
      } else {
        addLog("Failed to delete video: ${response.statusCode}");
      }
    } catch (e) {
      addLog("Error deleting video: $e");
    }
    return false;
  }
}
