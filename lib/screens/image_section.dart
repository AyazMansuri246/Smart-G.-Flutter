

import 'dart:async';
import 'dart:convert'; 
import 'dart:typed_data'; 
import 'dart:io'; 
// (we’ll talk about this below) 
import 'package:flutter/material.dart'; 
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http; 
import 'package:gal/gal.dart'; 
// swtich to gal 
import 'package:permission_handler/permission_handler.dart'; 
import 'package:provider/provider.dart'; 
import '../services/esp32_service.dart'; 
import '../utils/styles.dart';

class ImageSection extends StatelessWidget {
  const ImageSection({super.key});

  Future<void> _saveImage(
    BuildContext context,
    Uint8List imageBytes,
  ) async {
    try {
      if (Platform.isAndroid ||
          await Permission.photos.request().isGranted ||
          await Permission.storage.request().isGranted) {
        await Gal.putImageBytes(
          imageBytes,
          name: "esp32_${DateTime.now().millisecondsSinceEpoch}",
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Image saved to gallery")),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Permission denied")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Save failed: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final espService = context.watch<Esp32Service>();

    final images = espService.images;
    final preview = espService.previewImage;
    final isLoading = espService.isLoading;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          /// 🔼 Image Preview
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.4,
            width: double.infinity,
            child: Container(
              decoration: AppStyles.cardDecoration,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: preview != null
                    ? Image.memory(preview, fit: BoxFit.contain)
                    : const Center(
                        child: Text(
                          "Select an image to view",
                          style: AppStyles.subtitleStyle,
                        ),
                      ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          /// 🔄 Controls
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: espService.fetchImages,
                    icon: const Icon(Icons.refresh),
                    label: const Text("Load List"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: preview == null
                        ? null
                        : () => _saveImage(context, preview),
                    icon: const Icon(Icons.download),
                    label: const Text("Download"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.secondary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          /// 🔽 Image List
          const Align(
            alignment: Alignment.centerLeft,
            child: Text("Saved Images", style: AppStyles.titleStyle),
          ),
          const SizedBox(height: 8),

          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : images.isEmpty
                    ? const Center(
                        child: Text(
                          "No images found",
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        itemCount: images.length,
                        itemBuilder: (context, index) {
                          final imgName = images[index];
                          return Card(
                            elevation: 1,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              leading: const Icon(
                                Icons.image,
                                color: AppColors.secondary,
                              ),
                              title: Text(
                                imgName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              trailing: const Icon(
                                Icons.chevron_right,
                                color: Colors.grey,
                              ),
                              onTap: () =>
                                  espService.loadPreview(imgName),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
