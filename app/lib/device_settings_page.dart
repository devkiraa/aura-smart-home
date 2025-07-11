import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:aura_app/main.dart'; // Assuming main.dart contains AuraController

// Data model for a single appliance configuration
class ApplianceConfig {
  String name;
  int pin;

  ApplianceConfig({required this.name, required this.pin});

  Map<String, dynamic> toJson() => {'name': name, 'pin': pin, 'type': 'Light'};
  factory ApplianceConfig.fromJson(Map<String, dynamic> json) {
    return ApplianceConfig(name: json['name'], pin: json['pin']);
  }
}

class DeviceSettingsPage extends StatefulWidget {
  final AuraController controller;
  const DeviceSettingsPage({super.key, required this.controller});

  @override
  State<DeviceSettingsPage> createState() => _DeviceSettingsPageState();
}

class _DeviceSettingsPageState extends State<DeviceSettingsPage> {
  List<ApplianceConfig> _appliances = [];
  bool _isLoading = true;

  final List<int> safeGpioPins = [4, 5, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 23, 25, 26, 27, 32, 33];

  @override
  void initState() {
    super.initState();
    _loadConfiguration();
  }

  Future<void> _loadConfiguration() async {
    try {
      final response = await http.get(Uri.parse('http://${widget.controller.ip}/config'));
      if (response.statusCode == 200) {
        final List<dynamic> configData = jsonDecode(response.body);
        setState(() {
          _appliances = configData.map((data) => ApplianceConfig.fromJson(data)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Failed to load config: $e");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveConfiguration() async {
    try {
      final configJson = jsonEncode(_appliances.map((a) => a.toJson()).toList());
      final response = await http.post(
        Uri.parse('http://${widget.controller.ip}/config'),
        headers: {'Content-Type': 'application/json'},
        body: configJson,
      );
      if (response.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Configuration saved! Device is restarting.")),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      print("Failed to save config: $e");
    }
  }

  void _showAddApplianceDialog() {
    final nameController = TextEditingController();
    int? selectedPin = safeGpioPins.first;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Add Appliance"),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: "Appliance Name")),
            DropdownButton<int>(
              value: selectedPin,
              isExpanded: true,
              items: safeGpioPins.map((int pin) => DropdownMenuItem<int>(value: pin, child: Text("GPIO $pin"))).toList(),
              onChanged: (int? newValue) => setState(() => selectedPin = newValue),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.isNotEmpty && selectedPin != null) {
                  setState(() => _appliances.add(ApplianceConfig(name: nameController.text, pin: selectedPin!)));
                  Navigator.of(context).pop();
                }
              },
              child: const Text("Add"),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Configure ${widget.controller.name}"),
        actions: [IconButton(icon: const Icon(Icons.save), onPressed: _saveConfiguration)],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _appliances.length,
              itemBuilder: (context, index) {
                final appliance = _appliances[index];
                return ListTile(
                  leading: const Icon(Icons.power_outlined),
                  title: Text(appliance.name),
                  subtitle: Text("GPIO ${appliance.pin}"),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => setState(() => _appliances.removeAt(index)),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddApplianceDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}