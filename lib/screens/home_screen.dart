import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/styles.dart';
import '../services/esp32_service.dart';
import 'image_section.dart';
import 'recording_section.dart';
import 'speech_section.dart';
import 'live_translation_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  static const List<Widget> _pages = [
    ImageSection(),
    RecordingSection(),
    SpeechSection(),
    LiveTranslationScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _showLogs(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const LogViewerDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Smart View', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: SafeArea(
        child: _pages.elementAt(_selectedIndex),
      ),
      floatingActionButton: FloatingActionButton( 
        onPressed: () => _showLogs(context),
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.list_alt, color: Colors.white),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: BottomNavigationBar(
          items: const <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: Icon(Icons.image),
              label: 'Image',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.videocam),
              label: 'Recording',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.record_voice_over),
              label: 'Speech',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.translate),
              label: 'Live',
            ),
          ],
          currentIndex: _selectedIndex,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.textSub,
          onTap: _onItemTapped,
          backgroundColor: Colors.white,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
        ),
      ),
    );
  }
}

class LogViewerDialog extends StatelessWidget {
  const LogViewerDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final espService = Provider.of<Esp32Service>(context);

    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history, color: AppColors.primary, size: 28),
              const SizedBox(width: 10),
              const Text("System Logs", style: AppStyles.titleStyle),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent), 
                onPressed: espService.clearLogs
              ),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            "Tracking device activity on 192.168.4.1", 
            style: TextStyle(color: Colors.grey, fontSize: 13)
          ),
          const SizedBox(height: 20),
          
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: ListView.builder(
                itemCount: espService.logs.length,
                itemBuilder: (context, index) {
                  final log = espService.logs[espService.logs.length - 1 - index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(">", style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(log, style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
