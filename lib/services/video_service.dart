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

  final Map<String, DateTime> _localFileDates = {};
  DateTime? getFileDate(String videoName) => _localFileDates[videoName];

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
          _localFileDates[name] = file.lastModifiedSync();
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

  Future<void> _downloadAndProcess(String folderName) async {
    try {
      _videoStatuses[folderName] = VideoStatus.downloading;
      _downloadProgress[folderName] = 0.0;
      notifyListeners();

      final tempDir = await getTemporaryDirectory();
      final videoFile = File('${tempDir.path}/${folderName}_video.avi');
      final audioFile = File('${tempDir.path}/${folderName}_audio.wav');

      // 1. Download Video
      espService.addLog("Downloading video... $folderName");
      final videoStream = await espService.downloadFileStream(folderName, "video");
      if (videoStream == null) {
        throw Exception("Failed to get video stream");
      }
      
      final vSink = videoFile.openWrite();
      int vBytes = 0;
      await videoStream.forEach((chunk) {
        vSink.add(chunk);
        vBytes += chunk.length;
        // Approximation: 0.0 -> 0.45
      });
      await vSink.flush(); 
      await vSink.close();
      
      if (await videoFile.length() == 0) throw Exception("Downloaded video is empty");
      
      _downloadProgress[folderName] = 0.5;
      notifyListeners();

      // 2. Download Audio
      espService.addLog("Downloading audio... $folderName");
      final audioStream = await espService.downloadFileStream(folderName, "audio");
      if (audioStream == null) {
        throw Exception("Failed to get audio stream");
      }

      final aSink = audioFile.openWrite();
      int aBytes = 0;
      await audioStream.forEach((chunk) {
        aSink.add(chunk);
        aBytes += chunk.length;
      });
      await aSink.flush();
      await aSink.close();

      if (await audioFile.length() == 0) throw Exception("Downloaded audio is empty");

      _downloadProgress[folderName] = 1.0;
      notifyListeners();

      // 3. Merge with FFmpeg
      _videoStatuses[folderName] = VideoStatus.processing;
      notifyListeners();

      final outputPath = (await getLocalVideoFile(folderName)).path;
      espService.addLog("Merging video and audio...");

      // -c:v libx264 -pix_fmt yuv420p -c:a aac
      // Using 'aac' for audio compatibility
      final command = '-y -i "${videoFile.path}" -i "${audioFile.path}" -c:v libx264 -pix_fmt yuv420p -c:a aac "$outputPath"';

      await FFmpegKit.execute(command).then((session) async {
        final returnCode = await session.getReturnCode();
        
        if (ReturnCode.isSuccess(returnCode)) {
          _videoStatuses[folderName] = VideoStatus.ready;
          if (!_localVideoNames.contains(folderName)) {
             _localVideoNames.add(folderName);
          }
          espService.addLog("Success! Video merged and saved to $outputPath");
          
          await _refreshLocalStatuses(); // Ensure list is up to date
        } else {
          _videoStatuses[folderName] = VideoStatus.error;
          final logs = await session.getLogs();
          espService.addLog("FFmpeg Failed. Code: $returnCode");
          if (logs.isNotEmpty) {
             espService.addLog("FFmpeg Log: ${logs.last.getMessage()}");
          }
        }
        
        // Cleanup temp files
        if (await videoFile.exists()) await videoFile.delete();
        if (await audioFile.exists()) await audioFile.delete();
        
        notifyListeners();
      });

    } catch (e) {
      _videoStatuses[folderName] = VideoStatus.error;
      espService.addLog("Error processing $folderName: $e");
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
