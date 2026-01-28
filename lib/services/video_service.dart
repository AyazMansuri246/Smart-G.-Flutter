import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'esp32_service.dart';

enum VideoStatus {
  notDownloaded,
  downloading,
  processing,
  ready,
  error
}

class VideoService extends ChangeNotifier {
  final Esp32Service espService;
  Map<String, VideoStatus> _videoStatuses = {};
  Map<String, double> _downloadProgress = {};
  List<String> _localVideoNames = [];
  bool _isInitialized = false;

  VideoService(this.espService) {
    init();
  }

  VideoStatus getStatus(String videoName) => _videoStatuses[videoName] ?? VideoStatus.notDownloaded;
  double getProgress(String videoName) => _downloadProgress[videoName] ?? 0.0;
  List<String> get localVideoNames => _localVideoNames;

  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  Future<File> getLocalVideoFile(String videoName) async {
    final path = await _localPath;
    return File('$path/videos/$videoName.mp4');
  }

  Future<void> init() async {
    if (_isInitialized) return;
    
    final path = await _localPath;
    final videoDir = Directory('$path/videos');
    if (!await videoDir.exists()) {
      await videoDir.create(recursive: true);
    }
    
    await _refreshLocalStatuses();
    _isInitialized = true;
  }

  Future<void> _refreshLocalStatuses() async {
    final path = await _localPath;
    final videoDir = Directory('$path/videos');
    _localVideoNames.clear();
    if (await videoDir.exists()) {
      final files = videoDir.listSync();
      for (var file in files) {
        if (file is File && file.path.endsWith('.mp4')) {
          final name = file.path.split(Platform.pathSeparator).last.replaceFirst('.mp4', '');
          _videoStatuses[name] = VideoStatus.ready;
          if (!_localVideoNames.contains(name)) {
            _localVideoNames.add(name);
          }
        }
      }
    }
    notifyListeners();
  }

  Future<void> processVideos(List<String> videoNames) async {
    for (var name in videoNames) {
      if (getStatus(name) == VideoStatus.notDownloaded) {
        await _downloadAndProcess(name); // Run sequentially
      }
    }
  }

  Future<void> _downloadAndProcess(String videoName) async {
    try {
      _videoStatuses[videoName] = VideoStatus.downloading;
      _downloadProgress[videoName] = 0.0;
      notifyListeners();

      final stream = await espService.downloadVideoStream(videoName);
      
      if (stream == null) {
        espService.addLog("Error: Failed to initiate download stream for $videoName");
        _videoStatuses[videoName] = VideoStatus.error;
        notifyListeners();
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final aviFile = File('${tempDir.path}/$videoName');
      espService.addLog("Storage: Preparing temp file at ${aviFile.path}");
      
      // Write stream to file
      final sink = aviFile.openWrite();
      int receivedBytes = 0;
      // We don't know total size easily without Content-Length header from ESP32, 
      // but we can just show activity.
      
      try {
        await stream.forEach((chunk) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          // Animate progress arbitrarily or based on estimate since we might not have total size
          if (receivedBytes % (1024 * 100) == 0) { // Every 100KB update logs/UI (optional)
             // Update logic if we had total size
          }
        });
        await sink.flush();
        await sink.close();
        espService.addLog("Storage: Download complete. Bytes written: $receivedBytes");
      } catch (e) {
        await sink.close();
        espService.addLog("Storage: Error writing to file: $e");
        throw e;
      }

      _downloadProgress[videoName] = 1.0;
      notifyListeners();

      // Check if file is valid/empty
      int fileSize = await aviFile.length();
      if (fileSize == 0) {
         espService.addLog("Error: Downloaded file is empty (0 bytes).");
         _videoStatuses[videoName] = VideoStatus.error;
         notifyListeners();
         return;
      } else {
         espService.addLog("Storage: Temp file verified. Size: ${(fileSize/1024).toStringAsFixed(2)} KB");
      }

      _videoStatuses[videoName] = VideoStatus.processing;
      notifyListeners();

      final outputPath = (await getLocalVideoFile(videoName)).path;
      espService.addLog("FFmpeg: Starting conversion...");
      espService.addLog("FFmpeg: Input: ${aviFile.path}");
      espService.addLog("FFmpeg: Output: $outputPath");

      // FFmpeg command to convert MJPEG AVI to H.264 MP4
      // Added -f avi to force input format detection if header is slightly off
      final ffmpegCommand = '-y -i "${aviFile.path}" -c:v libx264 -pix_fmt yuv420p "$outputPath"';
      
      await FFmpegKit.execute(ffmpegCommand).then((session) async {
        final returnCode = await session.getReturnCode();
        final logs = await session.getLogs();
        
        if (ReturnCode.isSuccess(returnCode)) {
          _videoStatuses[videoName] = VideoStatus.ready;
          if (!_localVideoNames.contains(videoName)) {
             _localVideoNames.add(videoName);
          }
          espService.addLog("Storage: Success! Video saved to $outputPath");
          // Check final file
           File finalFile = File(outputPath);
           if (await finalFile.exists()) {
             espService.addLog("Storage: Final MP4 size: ${await finalFile.length()} bytes");
           } else {
             espService.addLog("Storage Error: MP4 processing reported success but file missing!");
           }

        } else {
          _videoStatuses[videoName] = VideoStatus.error;
          espService.addLog("FFmpeg: Failed. Code: $returnCode");
          if (logs.isNotEmpty) {
             espService.addLog("FFmpeg Last Log: ${logs.last.getMessage()}");
          }
        }
        
        // Cleanup temp file
        if (await aviFile.exists()) {
          await aviFile.delete();
          espService.addLog("Storage: Temp file cleaned up.");
        }
        notifyListeners();
      });
      // final logs = await session.getLogs(); 
      // for (final log in logs) {
      //   espService.addLog("FFmpeg: ${log.getMessage()}");
      // }

    } catch (e) {
      _videoStatuses[videoName] = VideoStatus.error;
      espService.addLog("Error processing $videoName: $e");
      notifyListeners();
    }
  }

  Future<void> deleteLocalVideo(String videoName) async {
    try {
      final file = await getLocalVideoFile(videoName);
      if (await file.exists()) {
        await file.delete();
      }
      _videoStatuses.remove(videoName);
      _localVideoNames.remove(videoName);
      notifyListeners();
      espService.addLog("Local video $videoName deleted.");
    } catch (e) {
      espService.addLog("Error deleting local video: $e");
    }
  }
}
