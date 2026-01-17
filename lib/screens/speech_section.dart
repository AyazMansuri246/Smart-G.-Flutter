import 'package:flutter/material.dart';
import '../utils/styles.dart';

class SpeechSection extends StatefulWidget {
  const SpeechSection({super.key});

  @override
  State<SpeechSection> createState() => _SpeechSectionState();
}

class _SpeechSectionState extends State<SpeechSection> {
  String? _sourceLanguage = 'English';
  String? _destLanguage = 'Spanish';

  final List<String> _languages = ['English', 'Spanish', 'French', 'German', 'Italian', 'Chinese', 'Japanese'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Speech Translation", style: AppStyles.titleStyle),
          const SizedBox(height: 10),
          const Text("Select languages to translate speech.", style: AppStyles.subtitleStyle),
          const SizedBox(height: 30),

          // Source Language
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _sourceLanguage,
                isExpanded: true,
                icon: const Icon(Icons.mic, color: AppColors.primary),
                hint: const Text("Source Language"),
                onChanged: (String? newValue) {
                  setState(() => _sourceLanguage = newValue);
                },
                items: _languages.map<DropdownMenuItem<String>>((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
              ),
            ),
          ),
          
          const SizedBox(height: 20),
          const Center(child: Icon(Icons.arrow_downward, color: AppColors.textSub)),
          const SizedBox(height: 20),

          // Destination Language
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _destLanguage,
                isExpanded: true,
                icon: const Icon(Icons.volume_up, color: AppColors.secondary),
                hint: const Text("Destination Language"),
                onChanged: (String? newValue) {
                  setState(() => _destLanguage = newValue);
                },
                items: _languages.map<DropdownMenuItem<String>>((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
              ),
            ),
          ),
          
          const Spacer(),

          // Dictate Button Placeholder
          SizedBox(
            width: double.infinity,
            height: 60,
            child: ElevatedButton(
              onPressed: () {
                 ScaffoldMessenger.of(context).showSnackBar(
                   const SnackBar(content: Text('Listening... (Placeholder)')),
                 );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: const CircleBorder(),
                elevation: 4,
              ),
              child: const Icon(Icons.mic, size: 30, color: Colors.white),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
