import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../services/esp32_service.dart';
import '../utils/styles.dart';

class RecordingSection extends StatefulWidget {
  const RecordingSection({super.key});

  @override
  State<RecordingSection> createState() => _RecordingSectionState();
}

class _RecordingSectionState extends State<RecordingSection> {
  Uint8List? _currentFrame;
  bool _isStreaming = false;
  Timer? _timer;
  
  // Clean up timer when widget is removed
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toggleStream(Esp32Service service) {
    if (_isStreaming) {
      _stopStream(service);
    } else {
      _startStream(service);
    }
  }

  void _stopStream(Esp32Service service) {
    _timer?.cancel();
    setState(() => _isStreaming = false);
    service.addLog("Stream stopped");
  }

  void _startStream(Esp32Service service) {
    setState(() => _isStreaming = true);
    service.addLog("Stream started");
    // Start fetching frames rapidly
    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
        _fetchFrame(service.ipAddress);
    });
  }

  Future<void> _fetchFrame(String ip) async {
     try {
      // Use timestamp to prevent caching
      final uri = Uri.parse('http://$ip/capture?t=${DateTime.now().millisecondsSinceEpoch}');
      final response = await http.get(uri).timeout(const Duration(milliseconds: 1000));

      if (response.statusCode == 200 && mounted) {
        setState(() {
          _currentFrame = response.bodyBytes;
        });
      }
    } catch (e) {
       // Silent fail on individual frame errors to keep stream "alive" conceptually
       // typically logging every error in stream spams the log.
    }
  }

  @override
  Widget build(BuildContext context) {
    final espService = Provider.of<Esp32Service>(context);

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        children: [
          // Upper Part: Video Preview
          Expanded(
            flex: 3,
            child: Container(
              width: double.infinity,
              decoration: AppStyles.cardDecoration,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_currentFrame != null)
                      Image.memory(
                        _currentFrame!,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                        width: double.infinity,
                      )
                    else 
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.videocam_outlined, size: 80, color: AppColors.textSub.withOpacity(0.3)),
                          const SizedBox(height: 10),
                          const Text("Stream Offline", style: AppStyles.subtitleStyle),
                        ],
                      ),
                    
                    // Live Indicator
                    if (_isStreaming)
                      Positioned(
                        top: 15,
                        left: 15,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.circle, size: 10, color: Colors.white),
                              SizedBox(width: 5),
                              Text("LIVE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                            ],
                          ),
                        ),
                      )
                  ],
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 20),

          // Lower Part: Controls
          SizedBox(
            width: double.infinity,
            height: 56,
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _toggleStream(espService),
                    icon: Icon(_isStreaming ? Icons.stop : Icons.play_arrow),
                    label: Text(_isStreaming ? "Stop Stream" : "Start Stream"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isStreaming ? Colors.redAccent : AppColors.secondary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                       padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                 Expanded(
                  child: OutlinedButton.icon(
                     onPressed: () {
                         ScaffoldMessenger.of(context).showSnackBar(
                           const SnackBar(content: Text('Video saved! (Simulated)')),
                         );
                     },
                    icon: const Icon(Icons.download),
                    label: const Text("Save Video"),
                     style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                       padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
