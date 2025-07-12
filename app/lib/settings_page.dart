import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'main.dart'; // To get the AuraController model

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // State for all settings page features
  String _appVersion = "Loading...";
  String _firmwareMessage = "Check for new firmware releases.";
  bool _isFirmwareLoading = false;
  
  // State for Wi-Fi change
  final DatabaseReference _devicesRef = FirebaseDatabase.instance.ref('devices');
  AuraController? _selectedController;
  List<AuraController> _onlineControllers = [];
  
  final String githubRepo = "devkiraa/aura-smart-home";

  @override
  void initState() {
    super.initState();
    _getAppVersion();
  }

  Future<void> _getAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _appVersion = packageInfo.version);
  }

  // --- FIRMWARE UPDATE LOGIC ---
  Future<void> _checkForFirmwareUpdates() async {
    setState(() {
      _isFirmwareLoading = true;
      _firmwareMessage = "Checking GitHub...";
    });
    try {
      final releaseUrl = Uri.parse("https://api.github.com/repos/$githubRepo/releases/latest");
      final response = await http.get(releaseUrl);
      if (response.statusCode != 200) throw Exception("Failed to fetch from GitHub (Code: ${response.statusCode})");

      final data = jsonDecode(response.body);
      final latestVersionOnGithub = (data['tag_name'] as String).replaceAll('v', '');
      final downloadUrl = (data['assets'] as List).firstWhere((asset) => asset['name'] == 'firmware.bin')['browser_download_url'];

      final dbRef = FirebaseDatabase.instance.ref('firmware');
      final snapshot = await dbRef.child('latest_version').get();
      final currentVersionInCloud = snapshot.exists ? snapshot.value.toString() : "0.0";
      
      if (latestVersionOnGithub == currentVersionInCloud) {
        throw Exception("Firmware is already up to date (v$latestVersionOnGithub).");
      }
      
      await dbRef.set({'latest_version': latestVersionOnGithub, 'download_url': downloadUrl});
      setState(() => _firmwareMessage = "Success! Pushed v$latestVersionOnGithub to all devices.");
    } catch (e) {
      setState(() => _firmwareMessage = "Info: ${e.toString().replaceAll('Exception: ', '')}");
    } finally {
      setState(() => _isFirmwareLoading = false);
    }
  }
  
  // --- CHANGE WI-FI LOGIC ---
  void _showChangeWifiDialog() {
    if (_selectedController == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select a device first.")));
      return;
    }
    final ssidController = TextEditingController();
    final passwordController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Change Wi-Fi for\n${_selectedController!.name}", style: const TextStyle(fontSize: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: ssidController, decoration: const InputDecoration(labelText: "New Wi-Fi Name (SSID)")),
            const SizedBox(height: 8),
            TextField(controller: passwordController, obscureText: true, decoration: const InputDecoration(labelText: "Password")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              if (ssidController.text.isEmpty) return;
              final url = 'http://${_selectedController!.ip}/reconfigure-wifi';
              try {
                await http.post(
                  Uri.parse(url),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({'ssid': ssidController.text, 'pass': passwordController.text}),
                );
                if(mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Wi-Fi details sent. Device will restart.")));
                  Navigator.of(context).popUntil((route) => route.isFirst);
                }
              } catch (e) {
                print("Failed to reconfigure Wi-Fi: $e");
              }
            },
            child: const Text("Save & Restart"),
          ),
        ],
      ),
    );
  }

  Future<void> _signOut() async {
    await GoogleSignIn().signOut();
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // User Profile Card
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(children: [
                CircleAvatar(
                  radius: 30,
                  backgroundImage: user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
                  child: user?.photoURL == null ? const Icon(Icons.person, size: 30) : null,
                ),
                const SizedBox(height: 12),
                Text(user?.displayName ?? "Aura User", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text(user?.email ?? "", style: const TextStyle(fontSize: 14, color: Colors.grey)),
                const SizedBox(height: 16),
                TextButton.icon(icon: const Icon(Icons.logout, color: Colors.red), label: const Text("Log Out", style: TextStyle(color: Colors.red)), onPressed: _signOut),
              ]),
            ),
          ),
          const SizedBox(height: 20),

          // Firmware Update Card
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(children: [
                Text(_firmwareMessage, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 20),
                if (_isFirmwareLoading) const CircularProgressIndicator() else ElevatedButton.icon(
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text("Push Latest Firmware"),
                  onPressed: _checkForFirmwareUpdates,
                  style: ElevatedButton.styleFrom(foregroundColor: Colors.white, backgroundColor: Colors.black),
                ),
                const SizedBox(height: 8),
                TextButton(onPressed: () => launchUrl(Uri.parse("https://github.com/$githubRepo/releases"), mode: LaunchMode.externalApplication), child: const Text("View Releases on GitHub")),
              ]),
            ),
          ),
          const SizedBox(height: 20),

          // Change Wi-Fi Card
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text("Device Management", style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  StreamBuilder<DatabaseEvent>(
                    stream: _devicesRef.onValue,
                    builder: (context, snapshot) {
                      if (!snapshot.hasData || snapshot.data?.snapshot.value == null) return const Text("Searching for online devices...");
                      
                      Map<dynamic, dynamic> data = snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
                      _onlineControllers = [];
                      data.forEach((key, value) {
                        if (value['online'] == true) {
                          _onlineControllers.add(AuraController.fromFirebase(key, value));
                        }
                      });

                      if (_onlineControllers.isEmpty) return const Text("No online devices found.");
                      
                      // --- FIX IS HERE ---
                      // We now use the controller's unique ID (a String) for the value, not the object itself.
                      return DropdownButtonFormField<String>(
                        value: _selectedController?.id,
                        hint: const Text("Select an online device..."),
                        decoration: const InputDecoration(border: OutlineInputBorder()),
                        items: _onlineControllers.map((controller) {
                          return DropdownMenuItem(value: controller.id, child: Text(controller.name));
                        }).toList(),
                        onChanged: (String? selectedId) {
                          setState(() {
                            _selectedController = _onlineControllers.firstWhere((c) => c.id == selectedId);
                          });
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.wifi_password_outlined),
                    label: const Text("Change Wi-Fi Network"),
                    onPressed: _showChangeWifiDialog,
                    style: ElevatedButton.styleFrom(foregroundColor: Colors.white, backgroundColor: Theme.of(context).colorScheme.primary),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 40),
          Center(child: Text("ZERODAY App Version $_appVersion", style: const TextStyle(color: Colors.grey))),
        ],
      ),
    );
  }
}