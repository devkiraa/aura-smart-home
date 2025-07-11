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
  String _firmwareMessage = "Tap to check for firmware updates.";
  String _appVersion = "...";

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
      _firmwareMessage = "Checking GitHub for updates...";
    });

    try {
      final releaseUrl = Uri.parse("https://api.github.com/repos/$githubRepo/releases/latest");
      final response = await http.get(releaseUrl);

      if (response.statusCode != 200) {
        throw Exception("GitHub request failed (Code: ${response.statusCode})");
      }

      final data = jsonDecode(response.body);
      final latestVersion = (data['tag_name'] as String).replaceAll('v', '');
      final assets = data['assets'] as List;
      final firmware = assets.firstWhere(
        (asset) => asset['name'] == 'firmware.bin',
        orElse: () => null,
      );

      if (firmware == null) {
        throw Exception("No 'firmware.bin' found in latest release.");
      }

      final downloadUrl = firmware['browser_download_url'];
      final db = FirebaseDatabase.instance.ref('firmware');
      final current = await db.child('latest_version').get();
      final currentVersion = current.exists ? current.value.toString() : "0.0";

      if (latestVersion == currentVersion) {
        throw Exception("Already up to date (v$latestVersion).");
      }

      await db.set({
        'latest_version': latestVersion,
        'download_url': downloadUrl,
      });

      setState(() {
        _firmwareMessage = "Firmware v$latestVersion pushed successfully.";
      });
    } catch (e) {
      setState(() {
        _firmwareMessage = "Note: ${e.toString().replaceAll('Exception: ', '')}";
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
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Settings", style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.green[700],
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Container(
            color: Colors.green[700],
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundImage: user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
                  child: user?.photoURL == null ? const Icon(Icons.person, size: 30, color: Colors.white) : null,
                  backgroundColor: Colors.white12,
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user?.displayName ?? "Aura User",
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(user?.email ?? "",
                        style: const TextStyle(color: Colors.white70, fontSize: 14)),
                  ],
                )
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 2,
                  child: Column(
                    children: [
                      ListTile(
                        title: const Text("Firmware Update"),
                        subtitle: Text(_firmwareMessage),
                        trailing: _isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : IconButton(
                                icon: const Icon(Icons.system_update),
                                onPressed: _checkForUpdates,
                              ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        title: const Text("GitHub Releases"),
                        trailing: const Icon(Icons.open_in_new),
                        onTap: () {
                          launchUrl(
                            Uri.parse("https://github.com/$githubRepo/releases"),
                            mode: LaunchMode.externalApplication,
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                ListTile(
                  title: const Text("Sign Out", style: TextStyle(color: Colors.red)),
                  trailing: const Icon(Icons.logout, color: Colors.red),
                  onTap: _signOut,
                ),
                const SizedBox(height: 24),
                Center(
                  child: Text("Aura v$_appVersion", style: const TextStyle(color: Colors.grey)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
