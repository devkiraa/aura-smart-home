import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final String githubRepo = "devkiraa/aura-smart-home";
  bool _isLoading = false;
  String _firmwareMessage = "Press the button to check for new firmware.";
  String _appVersion = "Loading...";

  @override
  void initState() {
    super.initState();
    _getAppVersion();
  }

  Future<void> _getAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _appVersion = packageInfo.version;
      });
    }
  }

  Future<void> _checkForUpdates() async {
    setState(() {
      _isLoading = true;
      _firmwareMessage = "Checking for new releases on GitHub...";
    });

    try {
      final releaseUrl = Uri.parse("https://api.github.com/repos/$githubRepo/releases/latest");
      final response = await http.get(releaseUrl);

      if (response.statusCode != 200) {
        throw Exception("Failed to fetch from GitHub (Code: ${response.statusCode})");
      }

      final data = jsonDecode(response.body);
      final latestVersionOnGithub = (data['tag_name'] as String).replaceAll('v', '');
      final assets = data['assets'] as List;
      final firmwareAsset = assets.firstWhere(
            (asset) => asset['name'] == 'firmware.bin',
        orElse: () => null,
      );

      if (firmwareAsset == null) {
        throw Exception("'firmware.bin' not found in the latest GitHub release assets.");
      }

      final downloadUrl = firmwareAsset['browser_download_url'];
      final dbRef = FirebaseDatabase.instance.ref('firmware');
      final snapshot = await dbRef.child('latest_version').get();
      final currentVersionInFirebase = snapshot.exists ? snapshot.value.toString() : "0.0";

      if (latestVersionOnGithub == currentVersionInFirebase) {
        throw Exception("Firmware is already up to date (Version $latestVersionOnGithub).");
      }

      await dbRef.set({
        'latest_version': latestVersionOnGithub,
        'download_url': downloadUrl,
      });

      setState(() {
        _firmwareMessage = "Success! Pushed version $latestVersionOnGithub.";
      });

    } catch (e) {
      setState(() {
        _firmwareMessage = "Info: ${e.toString().replaceAll('Exception: ', '')}";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _signOut() async {
    await GoogleSignIn().signOut();
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      // Navigate back to the login screen and remove all previous routes
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings"),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // --- User Profile Section ---
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundImage: user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
                    child: user?.photoURL == null ? const Icon(Icons.person, size: 30) : null,
                  ),
                  const SizedBox(height: 12),
                  Text(user?.displayName ?? "Aura User", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(user?.email ?? "", style: const TextStyle(fontSize: 14, color: Colors.grey)),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    icon: const Icon(Icons.logout, color: Colors.red),
                    label: const Text("Log Out", style: TextStyle(color: Colors.red)),
                    onPressed: _signOut,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // --- Firmware Update Section ---
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Text(
                    _firmwareMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 20),
                  if (_isLoading)
                    const CircularProgressIndicator(color: Colors.black)
                  else
                    ElevatedButton(
                      onPressed: _checkForUpdates,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text("Check & Push Latest Firmware"),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // --- App Info Section ---
          OutlinedButton.icon(
            icon: const Icon(Icons.open_in_new),
            label: const Text("View GitHub Releases"),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.black54,
              side: const BorderSide(color: Colors.black12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              launchUrl(Uri.parse("https://github.com/$githubRepo/releases"), mode: LaunchMode.externalApplication);
            },
          ),
          const SizedBox(height: 40),
          Center(
            child: Text(
              "Aura App Version $_appVersion",
              style: const TextStyle(color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}