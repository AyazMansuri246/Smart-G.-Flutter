import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:gal/gal.dart';
import '../services/esp32_service.dart';
import '../services/video_service.dart';
import '../utils/styles.dart';

class RecordingSection extends StatefulWidget {
  const RecordingSection({super.key});

  @override
  State<RecordingSection> createState() => _RecordingSectionState();
}

class _RecordingSectionState extends State<RecordingSection> {
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    // Removed automatic fetch. Data will only load when the user clicks 'Refresh'.
  }

  Future<void> _loadVideos() async {
    if (_isRefreshing) return;
    
    setState(() => _isRefreshing = true);
    
    final espService = Provider.of<Esp32Service>(context, listen: false);
    final videoService = Provider.of<VideoService>(context, listen: false);
    
    if (espService.isConnected) {
      await espService.fetchVideos();
      // Auto-download removed to prioritize manual clicks only.
      setState(() => _isRefreshing = false);
    } else {
      setState(() => _isRefreshing = false);
    }
  }

  File? _previewFile;
  String? _previewName;
  VideoPlayerController? _previewController;

  @override
  void dispose() {
    _previewController?.dispose();
    super.dispose();
  }

  Future<void> _initializePreview(File file) async {
    final oldController = _previewController;

    _previewController = VideoPlayerController.file(file);
    await _previewController!.initialize();
    _previewController!.setLooping(true);
    _previewController!.play();

    setState(() {});
    
    await oldController?.dispose();
  }

  void _onVideoTap(String videoName, VideoStatus status) async {
    final espService = Provider.of<Esp32Service>(context, listen: false);
    final videoService = Provider.of<VideoService>(context, listen: false);
    
    // Log the user action
    espService.addLog("User Action: Clicked video '$videoName'");
    
    setState(() {
      _previewName = videoName;
    });

    if (status == VideoStatus.ready) {
      final file = await videoService.getLocalVideoFile(videoName);
      if (await file.exists()) {
        _previewFile = file;
        await _initializePreview(file);
      }
    } else if (status == VideoStatus.notDownloaded || status == VideoStatus.error) {
      // Auto-download on click
      videoService.processVideos([videoName]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final espService = Provider.of<Esp32Service>(context);
    final videoService = Provider.of<VideoService>(context);

    final localVideos = videoService.localVideoNames;
    final remoteVideos = espService.videos;
    // Combine and sort (optional)
    final videos = {...remoteVideos, ...localVideos}.toList();

    // Determine preview state
    final isPreviewReady = _previewController != null && _previewController!.value.isInitialized;
    
    // Status of currently selected video for preview area
    final previewStatus = _previewName != null ? videoService.getStatus(_previewName!) : VideoStatus.notDownloaded;
    
    return Column(
      children: [
        // ---------------------------------------------
        // 1. Top Preview Area
        // ---------------------------------------------
        Container(
          height: MediaQuery.of(context).size.height * 0.35,
          width: double.infinity,
          margin: const EdgeInsets.all(16),
          decoration: AppStyles.cardDecoration.copyWith(
            color: Colors.black,
            borderRadius: BorderRadius.circular(20),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (isPreviewReady) 
                  Stack(
                    children: [
                      Center(
                        child: AspectRatio(
                          aspectRatio: _previewController!.value.aspectRatio,
                          child: VideoPlayer(_previewController!),
                        ),
                      ),
                      // YouTube Style Controls Overlay
                      VideoPlayerOverlay(controller: _previewController!),
                    ],
                  )
                else if (_previewName != null)
                   Column(
                     mainAxisAlignment: MainAxisAlignment.center,
                     children: [
                       // Show specific UI based on status
                       if (previewStatus == VideoStatus.downloading || previewStatus == VideoStatus.processing) ...[
                          const CircularProgressIndicator(color: AppColors.primary),
                          const SizedBox(height: 15),
                          Text(
                             previewStatus == VideoStatus.downloading ? "Downloading from ESP32..." : "Optimizing Video...",
                             style: const TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 5),
                          if (previewStatus == VideoStatus.downloading)
                             Text("${(videoService.getProgress(_previewName!) * 100).toInt()}%", style: const TextStyle(color: Colors.white38, fontSize: 12)),
                       ] else if (previewStatus == VideoStatus.error) ...[
                          Icon(Icons.error_outline, size: 50, color: Colors.red[300]),
                          const SizedBox(height: 10),
                          const Text("Download Failed", style: TextStyle(color: Colors.redAccent)),
                          TextButton(
                            onPressed: () => videoService.processVideos([_previewName!]),
                            child: const Text("Retry"),
                          )
                       ] else ...[
                          Icon(Icons.ondemand_video, size: 50, color: Colors.grey[700]),
                          const SizedBox(height: 10),
                          Text(
                            "Selected: $_previewName",
                            style: const TextStyle(color: Colors.white70),
                          ),
                          // It should auto-download, but if it stuck or sitting idle:
                           if (previewStatus == VideoStatus.notDownloaded)
                             const Padding(
                               padding: EdgeInsets.only(top:8.0),
                               child: Text("Fetching...", style: TextStyle(color: Colors.white30, fontSize: 10)),
                             ),
                       ]
                     ],
                   )
                else
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.touch_app, size: 50, color: Colors.grey[800]),
                      const SizedBox(height: 10),
                      Text(
                        "Select a video from the list", 
                        style: TextStyle(color: Colors.grey[600]),
                      )
                    ],
                  ),
                  
              ],
            ),
          ),
        ),

        
        // ---------------------------------------------
        // 2. Control & Status Bar
        // ---------------------------------------------
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
               Column(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                   const Text("Recordings", style: AppStyles.headerStyle),
                   Text("${videos.length} videos available", style: AppStyles.subtitleStyle.copyWith(fontSize: 12)),
                 ],
               ),
               IconButton(
                 onPressed: _loadVideos,
                 icon: _isRefreshing 
                     ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
                     : const Icon(Icons.refresh, color: AppColors.primary),
               ),
            ],
          ),
        ),
        
        const SizedBox(height: 10),

        // ---------------------------------------------
        // 3. Video List
        // ---------------------------------------------
        Expanded(
          child: videos.isEmpty && !espService.isLoading
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("No recordings found", style: AppStyles.subtitleStyle),
                      TextButton(onPressed: _loadVideos, child: const Text("Refresh"))
                    ],
                  ),
                )
              : Builder(
                  builder: (context) {
                    // Grouping Logic
                    final remoteList = <String>[];
                    final localList = <String>[];
                    
                    for (var v in videos) {
                       if (videoService.getStatus(v) == VideoStatus.ready) {
                         localList.add(v);
                       } else {
                         remoteList.add(v);
                       }
                    }

                    // Sort local by date desc
                    localList.sort((a, b) {
                       final dateA = videoService.getFileDate(a) ?? DateTime.fromMillisecondsSinceEpoch(0);
                       final dateB = videoService.getFileDate(b) ?? DateTime.fromMillisecondsSinceEpoch(0);
                       return dateB.compareTo(dateA);
                    });

                    final items = <dynamic>[];
                    
                    if (remoteList.isNotEmpty) {
                      items.add("New Recordings"); // Header
                      items.addAll(remoteList);
                    }
                    
                    if (localList.isNotEmpty) {
                       DateTime? lastDate;
                       for (var name in localList) {
                          final date = videoService.getFileDate(name);
                          if (date != null) {
                             final day = DateTime(date.year, date.month, date.day);
                             final lastDay = lastDate != null ? DateTime(lastDate.year, lastDate.month, lastDate.day) : null;
                             
                             if (lastDay == null || day != lastDay) {
                                String header = "${day.day}/${day.month}/${day.year}";
                                final now = DateTime.now();
                                final today = DateTime(now.year, now.month, now.day);
                                final yesterday = today.subtract(const Duration(days: 1));
                                
                                if (day == today) header = "Today";
                                else if (day == yesterday) header = "Yesterday";
                                
                                items.add(header);
                                lastDate = date;
                             }
                          } else {
                             // No date found
                             if (lastDate != null) {
                                items.add("Unknown Date");
                                lastDate = null; 
                             }
                          }
                          items.add(name);
                       }
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      physics: const BouncingScrollPhysics(),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        
                        if (item is String && !videos.contains(item)) {
                           // It's a header (since video names are strings too, we filter by ensuring it's not in the video list, 
                           // BUT wait, a video name could ostensibly be "Today". Unlikely but risky.
                           // Better to use a wrapper, but for now this check handles "New Recordings", "Today", "Yesterday" which are unlikely video names.
                           // Actually "Video_..." is the format.
                           return Padding(
                             padding: const EdgeInsets.only(top: 16, bottom: 8, left: 4),
                             child: Text(
                               item, 
                               style: TextStyle(
                                 color: Colors.grey[600], 
                                 fontWeight: FontWeight.bold, 
                                 fontSize: 14
                               )
                             ),
                           );
                        }
                        
                        final videoName = item as String;
                        final status = videoService.getStatus(videoName);
                        final progress = videoService.getProgress(videoName);
                        final isSelected = videoName == _previewName;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: InkWell(
                            onTap: () => _onVideoTap(videoName, status),
                            borderRadius: BorderRadius.circular(15),
                            child: Container(
                              decoration: isSelected ? BoxDecoration(
                                border: Border.all(color: AppColors.primary, width: 2),
                                borderRadius: BorderRadius.circular(15), 
                              ) : null,
                              child: VideoListTile(
                                videoName: videoName,
                                status: status,
                                progress: progress,
                                onPlay: () => _onVideoTap(videoName, status),
                                onDownload: () {
                                  if (status == VideoStatus.ready) {
                                    _downloadToGallery(videoName);
                                  } else {
                                    videoService.processVideos([videoName]);
                                  }
                                },
                                onDelete: () => _showDeleteOptions(videoName),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  }
                ),
        ),
      ],
    );
  }

  void _playVideo(String videoName) async {
    final videoService = Provider.of<VideoService>(context, listen: false);
    final file = await videoService.getLocalVideoFile(videoName);
    
    if (await file.exists()) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => VideoPlayerDialog(file: file, title: videoName),
      );
    }
  }

  void _downloadToGallery(String videoName) async {
    final espService = Provider.of<Esp32Service>(context, listen: false);
    final videoService = Provider.of<VideoService>(context, listen: false);
    
    espService.addLog("Gallery: Requesting save for $videoName...");
    final file = await videoService.getLocalVideoFile(videoName);
    
    if (await file.exists()) {
      try {
        espService.addLog("Gallery: File found at ${file.path}. Saving...");
        await Gal.putVideo(file.path);
        if (!mounted) return;
        
        espService.addLog("Gallery: Success! Video saved.");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Video saved to gallery!'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        espService.addLog("Gallery Error: $e");
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving video: $e')),
        );
      }
    } else {
      espService.addLog("Gallery Error: Local file not found for $videoName");
    }
  }

  void _showDeleteOptions(String videoName) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(25),
            topRight: Radius.circular(25),
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text("Manage $videoName", style: AppStyles.headerStyle),
              const SizedBox(height: 10),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.delete_outline, color: Colors.orange),
                ),
                title: const Text("Delete Locally"),
                subtitle: const Text("Remove MP4 from phone memory"),
                onTap: () {
                  Navigator.pop(context);
                  Provider.of<VideoService>(context, listen: false).deleteLocalVideo(videoName);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.delete_forever, color: Colors.red),
                ),
                title: const Text("Delete from ESP32"),
                subtitle: const Text("Permanently delete AVI file from SD card"),
                onTap: () async {
                  Navigator.pop(context);
                  final success = await Provider.of<Esp32Service>(context, listen: false).deleteVideo(videoName);
                  if (success) {
                    if (!mounted) return;
                    Provider.of<VideoService>(context, listen: false).deleteLocalVideo(videoName);
                  }
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}

class VideoListTile extends StatelessWidget {
  final String videoName;
  final VideoStatus status;
  final double progress;
  final VoidCallback onPlay;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  const VideoListTile({
    super.key,
    required this.videoName,
    required this.status,
    required this.progress,
    required this.onPlay,
    required this.onDownload,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    bool isReady = status == VideoStatus.ready;
    bool isProcessing = status == VideoStatus.processing || status == VideoStatus.downloading;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: AppStyles.cardDecoration.copyWith(
        border: isReady ? Border.all(color: AppColors.secondary.withOpacity(0.3)) : null,
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            // Video Preview Placeholder
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: isReady ? AppColors.secondary.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(
                isReady ? Icons.play_circle_fill : Icons.videocam,
                color: isReady ? AppColors.secondary : Colors.grey,
                size: 30,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(videoName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  _buildStatusSubtitle(),
                ],
              ),
            ),
            
            if (isReady) ...[
              _buildActionButton(Icons.play_arrow, AppColors.primary, onPlay),
              const SizedBox(width: 8),
              _buildActionButton(Icons.file_download_outlined, AppColors.secondary, onDownload),
            ] else if (isProcessing)
              _buildProcessingIndicator()
            else 
              _buildActionButton(Icons.cloud_download_outlined, Colors.grey, onDownload),
              
            const VerticalDivider(width: 24, indent: 10, endIndent: 10),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.more_vert, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }

  Widget _buildProcessingIndicator() {
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: status == VideoStatus.downloading ? progress : null,
            strokeWidth: 3,
            color: AppColors.primary,
            backgroundColor: AppColors.primary.withOpacity(0.1),
          ),
          if (status == VideoStatus.downloading)
            Text("${(progress * 100).toInt()}", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildStatusSubtitle() {
    switch (status) {
      case VideoStatus.notDownloaded:
        return const Row(
          children: [
            Icon(Icons.cloud_queue, size: 12, color: Colors.grey),
            SizedBox(width: 4),
            Text("On ESP32", style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        );
      case VideoStatus.downloading:
        return Row(
          children: [
             SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 2, value: progress, color: AppColors.primary)),
             const SizedBox(width: 6),
             const Text("Syncing...", style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        );
      case VideoStatus.processing:
        return const Text("Optimizing Video...", style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w500));
      case VideoStatus.ready:
        return Row(
          children: [
            Icon(Icons.check_circle, size: 12, color: Colors.green[600]),
            const SizedBox(width: 4),
            Text("Ready to watch", style: TextStyle(color: Colors.green[600], fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        );
      case VideoStatus.error:
        return const Row(
          children: [
            Icon(Icons.error_outline, size: 12, color: Colors.red),
            SizedBox(width: 4),
            Text("Processing failed", style: TextStyle(color: Colors.red, fontSize: 12)),
          ],
        );
    }
  }
}

class VideoPlayerDialog extends StatefulWidget {
  final File file;
  final String title;

  const VideoPlayerDialog({super.key, required this.file, required this.title});

  @override
  State<VideoPlayerDialog> createState() => _VideoPlayerDialogState();
}

class _VideoPlayerDialogState extends State<VideoPlayerDialog> {
  late VideoPlayerController _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file)
      ..initialize().then((_) {
        setState(() {
          _initialized = true;
          _controller.play();
          _controller.setLooping(true);
        });
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppBar(
            backgroundColor: Colors.black,
            elevation: 0,
            title: Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 16)),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
               IconButton(
                 icon: const Icon(Icons.share, color: Colors.white),
                 onPressed: () {
                    // Could add sharing here
                 },
               ),
            ],
          ),
          Expanded(
            child: Center(
              child: _initialized
                  ? AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: Stack(
                        alignment: Alignment.bottomCenter,
                        children: [
                          VideoPlayer(_controller),
                          VideoProgressIndicator(_controller, allowScrubbing: true, colors: const VideoProgressColors(playedColor: AppColors.primary)),
                        ],
                      ),
                    )
                  : const CircularProgressIndicator(color: Colors.white),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            color: Colors.black,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: const Icon(Icons.replay_10, color: Colors.white, size: 30),
                  onPressed: () => _controller.seekTo(_controller.value.position - const Duration(seconds: 10)),
                ),
                FloatingActionButton(
                  backgroundColor: AppColors.primary,
                  onPressed: () {
                    setState(() {
                      _controller.value.isPlaying ? _controller.pause() : _controller.play();
                    });
                  },
                  child: Icon(_controller.value.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
                ),
                IconButton(
                  icon: const Icon(Icons.forward_10, color: Colors.white, size: 30),
                  onPressed: () => _controller.seekTo(_controller.value.position + const Duration(seconds: 10)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class VideoPlayerOverlay extends StatefulWidget {
  final VideoPlayerController controller;

  const VideoPlayerOverlay({super.key, required this.controller});

  @override
  State<VideoPlayerOverlay> createState() => _VideoPlayerOverlayState();
}

class _VideoPlayerOverlayState extends State<VideoPlayerOverlay> {
  bool _showControls = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _startHideTimer();
    widget.controller.addListener(_onControllerUpdate);
  }

  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    widget.controller.removeListener(_onControllerUpdate);
    super.dispose();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      if (_showControls) _startHideTimer();
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggleControls,
      behavior: HitTestBehavior.opaque,
      child: AnimatedOpacity(
        opacity: _showControls ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: Stack(
          children: [
            // Dark Overlay
            Container(color: Colors.black26),
            
            // Middle Controls (Rewind, Play/Pause, Forward)
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _circleIconButton(Icons.replay_10, () {
                    final newPos = widget.controller.value.position - const Duration(seconds: 10);
                    widget.controller.seekTo(newPos < Duration.zero ? Duration.zero : newPos);
                    _startHideTimer();
                  }),
                  _circleIconButton(
                    widget.controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                    () {
                      widget.controller.value.isPlaying ? widget.controller.pause() : widget.controller.play();
                      _startHideTimer();
                    },
                    isLarge: true,
                  ),
                  _circleIconButton(Icons.forward_10, () {
                    final newPos = widget.controller.value.position + const Duration(seconds: 10);
                    final max = widget.controller.value.duration;
                    widget.controller.seekTo(newPos > max ? max : newPos);
                    _startHideTimer();
                  }),
                ],
              ),
            ),

            // Bottom Bar (Progress, Time)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black54, Colors.transparent],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Seek Bar
                    VideoProgressIndicator(
                      widget.controller,
                      allowScrubbing: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      colors: const VideoProgressColors(
                        playedColor: AppColors.primary,
                        bufferedColor: Colors.white24,
                        backgroundColor: Colors.white10,
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          _formatDuration(widget.controller.value.position),
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                        const Text(" / ", style: TextStyle(color: Colors.white54, fontSize: 12)),
                        Text(
                          _formatDuration(widget.controller.value.duration),
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.fullscreen, color: Colors.white, size: 20),
                          onPressed: () {
                            // Fullscreen logic if needed
                          },
                        ),
                      ],
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

  Widget _circleIconButton(IconData icon, VoidCallback onTap, {bool isLarge = false}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(50),
        child: Container(
          padding: EdgeInsets.all(isLarge ? 16 : 12),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black38,
          ),
          child: Icon(icon, color: Colors.white, size: isLarge ? 32 : 24),
        ),
      ),
    );
  }
}
