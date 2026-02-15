import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:image_picker/image_picker.dart';
import '../utils/styles.dart';

class SpeechSection extends StatefulWidget {
  const SpeechSection({super.key});

  @override
  State<SpeechSection> createState() => _SpeechSectionState();
}

class _SpeechSectionState extends State<SpeechSection> {
  File? _image;
  String _extractedText = "";
  String _translatedText = "";
  bool _isProcessing = false;
  
  // Translation
  late OnDeviceTranslator _onDeviceTranslator;
  final _modelManager = OnDeviceTranslatorModelManager();
  TranslateLanguage _sourceLanguage = TranslateLanguage.english;
  TranslateLanguage _targetLanguage = TranslateLanguage.spanish;
  
  // Helper to get enum from string (if needed) or just use enums directly
  
  @override
  void initState() {
    super.initState();
    _initTranslator();
  }

  void _initTranslator() {
    _onDeviceTranslator = OnDeviceTranslator(
      sourceLanguage: _sourceLanguage,
      targetLanguage: _targetLanguage,
    );
  }

  @override
  void dispose() {
    _onDeviceTranslator.close();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source);

    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
        _extractedText = "";
        _translatedText = "";
      });
      _processImage();
    }
  }

  Future<void> _processImage() async {
    if (_image == null) return;

    setState(() => _isProcessing = true);

    try {
      // 1. Text Recognition (OCR)
      final inputImage = InputImage.fromFile(_image!);
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      
      String text = recognizedText.text;
      await textRecognizer.close();

      setState(() {
        _extractedText = text;
      });

      if (text.isEmpty) {
         setState(() {
           _translatedText = "No text found in image.";
           _isProcessing = false;
         });
         return;
      }

      // 2. Translation
      // Check if models are downloaded
      final bool isSourceDownloaded = await _modelManager.isModelDownloaded(_sourceLanguage.bcpCode);
      final bool isTargetDownloaded = await _modelManager.isModelDownloaded(_targetLanguage.bcpCode);

      if (!isSourceDownloaded) {
         // Optionally prompt user, but here we'll auto-download or show distinct status
         await _modelManager.downloadModel(_sourceLanguage.bcpCode);
      }
      if (!isTargetDownloaded) {
         await _modelManager.downloadModel(_targetLanguage.bcpCode);
      }
      
      // Re-init translator in case languages changed or purely to ensure freshness
      // (Though _onDeviceTranslator update logic is needed if languages change)
      
      final String translation = await _onDeviceTranslator.translateText(text);
      
      setState(() {
        _translatedText = translation;
      });

    } catch (e) {
      setState(() {
        _extractedText = "Error: $e";
      });
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _onLanguageChanged(TranslateLanguage? source, TranslateLanguage? target) async {
    if (source != null) _sourceLanguage = source;
    if (target != null) _targetLanguage = target;
    
    _onDeviceTranslator.close();
    _onDeviceTranslator = OnDeviceTranslator(
      sourceLanguage: _sourceLanguage,
      targetLanguage: _targetLanguage,
    );

    // If we already have text, re-translate
    if (_extractedText.isNotEmpty) {
       // We might need to handle the case where we are re-translating existing text
       // without re-OCR
       setState(() => _isProcessing = true);
       try {
          final bool isSourceDownloaded = await _modelManager.isModelDownloaded(_sourceLanguage.bcpCode);
          final bool isTargetDownloaded = await _modelManager.isModelDownloaded(_targetLanguage.bcpCode);
          
          if (!isSourceDownloaded) await _modelManager.downloadModel(_sourceLanguage.bcpCode);
          if (!isTargetDownloaded) await _modelManager.downloadModel(_targetLanguage.bcpCode);

          final translation = await _onDeviceTranslator.translateText(_extractedText);
          setState(() {
            _translatedText = translation;
          });
       } catch (e) {
         // handle error
       } finally {
         setState(() => _isProcessing = false);
       }
    } else {
      setState(() {});
    }
  }

  Future<void> _manageModel(TranslateLanguage language) async {
    final code = language.bcpCode;
    final isDownloaded = await _modelManager.isModelDownloaded(code);
    
    if (!mounted) return;

    if (isDownloaded) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text("Delete Model?"),
          content: Text("Do you want to delete the ${language.name} language model?"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text("Cancel")),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text("Delete", style: TextStyle(color: Colors.red))),
          ],
        ),
      );
      if (confirm == true) {
        await _modelManager.deleteModel(code);
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Deleted ${language.name} model")));
      }
    } else {
       await _modelManager.downloadModel(code);
       setState(() {});
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Downloaded ${language.name} model")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Image Translation", style: AppStyles.titleStyle),
          const SizedBox(height: 10),
          const Text("Extract and translate text from images.", style: AppStyles.subtitleStyle),
          const SizedBox(height: 20),

          // Languages
          Row(
            children: [
              Expanded(
                child: _buildLanguageSelector(
                  label: "Source",
                  value: _sourceLanguage,
                  onChanged: (val) => _onLanguageChanged(val, null),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.0),
                child: Icon(Icons.arrow_forward, color: AppColors.textSub),
              ),
              Expanded(
                child: _buildLanguageSelector(
                  label: "Dest",
                  value: _targetLanguage,
                  onChanged: (val) => _onLanguageChanged(null, val),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 20),

          // Image Area
          Expanded(
            child: SingleChildScrollView(
               child: Column(
                 crossAxisAlignment: CrossAxisAlignment.stretch,
                 children: [
                   GestureDetector(
                     onTap: () {
                       showModalBottomSheet(
                         context: context, 
                         builder: (ctx) => SafeArea(
                           child: Wrap(
                             children: [
                               ListTile(
                                 leading: Icon(Icons.photo_library),
                                 title: Text("Gallery"),
                                 onTap: () {
                                   Navigator.pop(ctx);
                                   _pickImage(ImageSource.gallery);
                                 },
                               ),
                               ListTile(
                                 leading: Icon(Icons.camera_alt),
                                 title: Text("Camera"),
                                 onTap: () {
                                   Navigator.pop(ctx);
                                   _pickImage(ImageSource.camera);
                                 },
                               ),
                             ],
                           ),
                         )
                       );
                     },
                     child: Container(
                       height: 200,
                       decoration: BoxDecoration(
                         color: Colors.grey[200],
                         borderRadius: BorderRadius.circular(15),
                         border: Border.all(color: Colors.grey[300]!),
                         image: _image != null ? DecorationImage(image: FileImage(_image!), fit: BoxFit.cover) : null,
                       ),
                       child: _image == null 
                         ? Center(
                             child: Column(
                               mainAxisAlignment: MainAxisAlignment.center,
                               children: [
                                 Icon(Icons.add_a_photo, size: 40, color: Colors.grey[400]),
                                 SizedBox(height: 8),
                                 Text("Tap to upload image", style: TextStyle(color: Colors.grey[600])),
                               ],
                             ),
                           )
                         : null,
                     ),
                   ),
                   
                   const SizedBox(height: 20),
                   
                   if (_isProcessing)
                      const Center(child: CircularProgressIndicator())
                   else ...[
                      // Extracted Text
                      if (_extractedText.isNotEmpty) ...[
                        Text("Extracted Text (${_sourceLanguage.name})", style: AppStyles.cardTitleStyle),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[200]!),
                          ),
                          child: Text(_extractedText, style: const TextStyle(fontSize: 15)),
                        ),
                        const SizedBox(height: 20),
                        
                        // Translated Text
                        Text("Translated Text (${_targetLanguage.name})", style: AppStyles.cardTitleStyle),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                          ),
                          child: Text(_translatedText, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.black87)),
                        ),
                      ]
                   ]
                 ],
               ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildLanguageSelector({
    required String label, 
    required TranslateLanguage value, 
    required Function(TranslateLanguage?) onChanged
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSub)),
        const SizedBox(height: 4),
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<TranslateLanguage>(
                    value: value,
                    isExpanded: true,
                    icon: const SizedBox.shrink(),
                    onChanged: onChanged,
                    items: TranslateLanguage.values.map((lang) {
                      return DropdownMenuItem(
                        value: lang,
                        child: Text(lang.name.toUpperCase(), overflow: TextOverflow.ellipsis, maxLines: 1, style: TextStyle(fontSize: 13)),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const Icon(Icons.arrow_drop_down, color: Colors.grey),
              
              // Download/Manage Icon
              FutureBuilder<bool>(
                future: _modelManager.isModelDownloaded(value.bcpCode),
                builder: (context, snapshot) {
                  final isDownloaded = snapshot.data ?? false;
                  return IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      isDownloaded ? Icons.check_circle : Icons.download,
                      size: 18,
                      color: isDownloaded ? Colors.green : Colors.orange,
                    ),
                    onPressed: () => _manageModel(value),
                  );
                }
              )
            ],
          ),
        ),
      ],
    );
  }
}
