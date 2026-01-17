import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/styles.dart';
import '../services/esp32_service.dart';
import 'image_section.dart';
import 'recording_section.dart';
import 'speech_section.dart';

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
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _showConnectionDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const ConnectionDialog(),
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
      floatingActionButton: _selectedIndex < 2 
          ? FloatingActionButton( // Only show FAB on Image/Recording tabs
              onPressed: () => _showConnectionDialog(context),
              backgroundColor: AppColors.secondary,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
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

class ConnectionDialog extends StatelessWidget {
  const ConnectionDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final espService = Provider.of<Esp32Service>(context);
    final ipController = TextEditingController(text: espService.ipAddress);

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
              const Icon(Icons.wifi, color: AppColors.primary, size: 28),
              const SizedBox(width: 10),
              const Text("Connect to Device", style: AppStyles.titleStyle),
              const Spacer(),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: 20),
          
          TextField(
            controller: ipController,
            decoration: InputDecoration(
              labelText: "ESP32 IP Address",
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              prefixIcon: const Icon(Icons.computer),
            ),
          ),
          const SizedBox(height: 16),
          
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () {
                espService.setIpAddress(ipController.text);
                espService.connect();
                FocusScope.of(context).unfocus(); // Request connect but stay in dialog to see logs
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("Connect"),
            ),
          ),
          
          const SizedBox(height: 24),
          const Text("Connection Logs", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const Divider(),
          
          Expanded(
            child: ListView.builder(
              itemCount: espService.logs.length,
              itemBuilder: (context, index) {
                // Show newest logs at top visually or bottom? 
                // Let's reverse access for UI so newest is at top or auto-scroll. 
                // Simple list is fine.
                final log = espService.logs[espService.logs.length - 1 - index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(log, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
