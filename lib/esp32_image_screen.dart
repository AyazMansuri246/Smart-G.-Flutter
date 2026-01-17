import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class Esp32ImageScreen extends StatefulWidget {
  const Esp32ImageScreen({super.key});

  @override
  State<Esp32ImageScreen> createState() => _Esp32ImageScreenState();
}

class _Esp32ImageScreenState extends State<Esp32ImageScreen> {
  final TextEditingController _ipController = TextEditingController(text: '192.168.1.100');
  Uint8List? _imageBytes;
  bool _isLoading = false;
  String? _errorMessage;
  Timer? _timer;
  bool _isAutoRefreshing = false;

  // Function to fetch image from ESP32
  Future<void> _fetchImage() async {
    // If we are auto-refreshing, we don't want to show the loading spinner every time
    // to avoid UI jitter, but for single fetch we do.
    if (!_isAutoRefreshing) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      // We assume the ESP32 serves the image at /capture or root.
      // Adjust the path '/capture' based on your specific ESP32 code.
      // Use timestamp to prevent caching
      final uri = Uri.parse('http://${_ipController.text}/capture?t=${DateTime.now().millisecondsSinceEpoch}');
      
      // Short timeout to prevent hanging UI
      final response = await http.get(uri).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        setState(() {
          _imageBytes = response.bodyBytes;
          _isLoading = false;
          _errorMessage = null;
        });
      } else {
        setState(() {
          _errorMessage = 'Error: ${response.statusCode} - ${response.reasonPhrase}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to connect: $e';
        _isLoading = false;
      });
      // specific logic: if auto refresh is on, maybe we want to stop it on error?
      // for now, we keep trying or let user stop it.
    }
  }

  void _toggleAutoRefresh() {
    if (_isAutoRefreshing) {
      _timer?.cancel();
      setState(() {
        _isAutoRefreshing = false;
      });
    } else {
      setState(() {
        _isAutoRefreshing = true;
      });
      // Fetch immediately
      _fetchImage();
      // Then fetch every 200ms (approx 5 fps)
      _timer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
        _fetchImage();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ESP32 Image Viewer'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Instructions
            const Text(
              "Ensure your ESP32 and this device are on the SAME Wi-Fi network.",
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 10),
            
            // Input Field
            TextField(
              controller: _ipController,
              decoration: const InputDecoration(
                labelText: 'ESP32 IP Address',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.wifi),
                hintText: 'e.g. 192.168.4.1',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            
            // Controls
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: (_isLoading && !_isAutoRefreshing) ? null : _fetchImage,
                  icon: const Icon(Icons.camera),
                  label: const Text('Capture'),
                ),
                ElevatedButton.icon(
                  onPressed: _toggleAutoRefresh,
                  icon: Icon(_isAutoRefreshing ? Icons.videocam_off : Icons.videocam),
                  label: Text(_isAutoRefreshing ? 'Stop Stream' : 'Stream'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isAutoRefreshing ? Colors.redAccent : Colors.teal,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            // Image Display
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.grey.shade100,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Center(
                    child: _buildImageContent(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageContent() {
    if (_errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.orange),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.black87),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    
    if (_imageBytes != null) {
      return Image.memory(
        _imageBytes!,
        gaplessPlayback: true, // Crucial for streaming to prevent flicker
        fit: BoxFit.contain,
        width: double.infinity,
      );
    }

    if (_isLoading) {
      return const CircularProgressIndicator();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: const [
        Icon(Icons.image_search, size: 64, color: Colors.grey),
        Text("No image loaded"),
      ],
    );
  }
}
