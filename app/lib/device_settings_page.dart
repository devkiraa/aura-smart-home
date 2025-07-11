import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:aura_app/main.dart'; 

// Data model for a single appliance configuration
class ApplianceConfig {
  String name;
  int pin;
  String type;

  ApplianceConfig({required this.name, required this.pin, this.type = "Light"});

  Map<String, dynamic> toJson() => {'name': name, 'pin': pin, 'type': type};
  
  factory ApplianceConfig.fromJson(Map<String, dynamic> json) {
    return ApplianceConfig(
      name: json['name'] ?? 'Unnamed',
      pin: json['pin'] ?? 0,
      type: json['type'] ?? 'Light',
    );
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
  bool _isSaving = false;

  final List<int> safeGpioPins = [4, 5, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 23, 25, 26, 27, 32, 33];

  @override
  void initState() {
    super.initState();
    _loadConfigurationFromFirestore();
  }

  Future<void> _loadConfigurationFromFirestore() async {
    setState(() => _isLoading = true);
    try {
      final docRef = FirebaseFirestore.instance.collection('device_configs').doc(widget.controller.id);
      final doc = await docRef.get();
      
      if (doc.exists && doc.data() != null && doc.data()!['appliances'] != null) {
        final List<dynamic> configData = doc.data()!['appliances'];
        if(mounted) {
          setState(() {
            _appliances = configData.map((data) => ApplianceConfig.fromJson(data)).toList();
          });
        }
      }
    } catch (e) {
      print("Failed to load config from Firestore: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not load saved configuration.")),
        );
      }
    } finally {
        if(mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveConfigurationToFirestore() async {
    setState(() => _isSaving = true);
    try {
      final docRef = FirebaseFirestore.instance.collection('device_configs').doc(widget.controller.id);
      final configToSave = _appliances.map((a) => a.toJson()).toList();
      
      await docRef.set({
        'controllerName': widget.controller.name,
        'appliances': configToSave,
      });

      // After saving, send a command to the Realtime Database to trigger a reboot
      final rtdbRef = FirebaseDatabase.instance.ref('devices/${widget.controller.id}/command');
      await rtdbRef.set('REBOOT');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Configuration saved! Device will restart to apply new settings.")),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      print("Failed to save config: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to save configuration to the cloud.")),
        );
      }
    } finally {
        if(mounted) setState(() => _isSaving = false);
    }
  }

  void _showAddApplianceDialog() {
    final usedPins = _appliances.map((a) => a.pin).toSet();
    final availablePins = safeGpioPins.where((pin) => !usedPins.contains(pin)).toList();

    if (availablePins.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No more available GPIO pins to configure.")),
      );
      return;
    }
    
    final nameController = TextEditingController();
    int? selectedPin = availablePins.first;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Add Appliance"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: "Appliance Name (e.g., Ceiling Fan)"),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    value: selectedPin,
                    decoration: const InputDecoration(labelText: "GPIO Pin", border: OutlineInputBorder()),
                    items: availablePins.map((int pin) => DropdownMenuItem<int>(value: pin, child: Text("GPIO $pin"))).toList(),
                    onChanged: (int? newValue) => setDialogState(() => selectedPin = newValue),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("Cancel")),
                ElevatedButton(
                  onPressed: () {
                    if (nameController.text.isNotEmpty && selectedPin != null) {
                      setState(() {
                        _appliances.add(ApplianceConfig(name: nameController.text, pin: selectedPin!));
                      });
                      Navigator.of(context).pop();
                    }
                  },
                  child: const Text("Add"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Configure ${widget.controller.name}"),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 3)),
            )
          else
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _isLoading ? null : _saveConfigurationToFirestore,
              tooltip: "Save Configuration",
            )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _appliances.isEmpty 
            ? const Center(child: Text("No appliances configured yet. Add one!"))
            : ListView.builder(
              padding: const EdgeInsets.only(bottom: 80), // Space for the FAB
              itemCount: _appliances.length,
              itemBuilder: (context, index) {
                final appliance = _appliances[index];
                return ListTile(
                  leading: const Icon(Icons.power_outlined),
                  title: Text(appliance.name),
                  subtitle: Text("Connected to GPIO ${appliance.pin}"),
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
        tooltip: "Add Appliance",
      ),
    );
  }
}