import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:aura_app/main.dart'; 
import 'package:aura_app/manage_rooms_page.dart';

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
  String? _selectedRoomId;
  bool _isLoading = true;
  bool _isSaving = false;

  final List<int> safeGpioPins = [4, 5, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 23, 25, 26, 27, 32, 33];
  final List<String> applianceTypes = ["Light", "Fan", "Socket", "Other"];

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
      
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final List<dynamic> configData = data['appliances'] ?? [];
        if(mounted) {
          setState(() {
            _selectedRoomId = data['roomId'];
            _appliances = configData.map((data) => ApplianceConfig.fromJson(data)).toList();
          });
        }
      }
    } catch (e) {
      print("Failed to load config from Firestore: $e");
    } finally {
        if(mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveConfigurationToFirestore() async {
    if (_selectedRoomId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please assign the controller to a room before saving.")),
      );
      return;
    }
    setState(() => _isSaving = true);
    try {
      final docRef = FirebaseFirestore.instance.collection('device_configs').doc(widget.controller.id);
      final configToSave = _appliances.map((a) => a.toJson()).toList();
      
      await docRef.set({
        'controllerName': widget.controller.name,
        'roomId': _selectedRoomId,
        'appliances': configToSave,
      });

      final rtdbRef = FirebaseDatabase.instance.ref('devices/${widget.controller.id}/command');
      await rtdbRef.set('REBOOT');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Configuration saved! Device will restart.")),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      print("Failed to save config: $e");
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
    String selectedType = applianceTypes.first;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Add Appliance"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: "Appliance Name"),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      value: selectedPin,
                      decoration: const InputDecoration(labelText: "GPIO Pin", border: OutlineInputBorder()),
                      items: availablePins.map((pin) => DropdownMenuItem<int>(value: pin, child: Text("GPIO $pin"))).toList(),
                      onChanged: (val) => setDialogState(() => selectedPin = val),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: selectedType,
                      decoration: const InputDecoration(labelText: "Appliance Type", border: OutlineInputBorder()),
                      items: applianceTypes.map((type) => DropdownMenuItem<String>(value: type, child: Text(type))).toList(),
                      onChanged: (val) => setDialogState(() => selectedType = val!),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("Cancel")),
                ElevatedButton(
                  onPressed: () {
                    if (nameController.text.isNotEmpty && selectedPin != null) {
                      setState(() {
                        _appliances.add(ApplianceConfig(name: nameController.text, pin: selectedPin!, type: selectedType));
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
  
  IconData getIconForType(String type) {
    switch (type) {
      case "Fan": return Icons.air_outlined;
      case "Socket": return Icons.power_outlined;
      case "Light":
      default:
        return Icons.lightbulb_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Configure ${widget.controller.name}"),
        actions: [
          if (_isSaving)
            const Padding(padding: EdgeInsets.all(16.0), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 3)))
          else
            IconButton(icon: const Icon(Icons.save), onPressed: _isLoading ? null : _saveConfigurationToFirestore, tooltip: "Save Configuration")
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser!.uid).collection('rooms').snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                      
                      final rooms = snapshot.data!.docs;

                      // --- THIS IS THE FIX ---
                      if (rooms.isEmpty) {
                        return Center(
                          child: Column(
                            children: [
                              const Text("No rooms found."),
                              const SizedBox(height: 8),
                              ElevatedButton(
                                onPressed: () {
                                  Navigator.of(context).push(MaterialPageRoute(builder: (context) => const ManageRoomsPage()));
                                },
                                child: const Text("Create a Room"),
                              )
                            ],
                          ),
                        );
                      }

                      return DropdownButtonFormField<String>(
                        value: _selectedRoomId,
                        hint: const Text("Assign to a Room"),
                        decoration: const InputDecoration(border: OutlineInputBorder()),
                        items: rooms.map((doc) => DropdownMenuItem(value: doc.id, child: Text(doc['name']))).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedRoomId = value;
                          });
                        },
                      );
                    },
                  ),
                ),
                const Divider(),
                Expanded(
                  child: _appliances.isEmpty
                      ? const Center(child: Text("No appliances configured yet. Add one!"))
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 80),
                          itemCount: _appliances.length,
                          itemBuilder: (context, index) {
                            final appliance = _appliances[index];
                            return ListTile(
                              leading: Icon(getIconForType(appliance.type)),
                              title: Text(appliance.name),
                              subtitle: Text("GPIO ${appliance.pin} • ${appliance.type}"),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                onPressed: () => setState(() => _appliances.removeAt(index)),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddApplianceDialog,
        tooltip: "Add Appliance",
        child: const Icon(Icons.add),
      ),
    );
  }
}