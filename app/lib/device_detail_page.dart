import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'main.dart'; // Contains AuraController and Appliance models
import 'device_settings_page.dart';

class DeviceDetailPage extends StatelessWidget {
  final AuraController controller;

  const DeviceDetailPage({super.key, required this.controller});

  Future<void> _toggleApplianceState(Appliance appliance) async {
    final url = 'http://${controller.ip}/toggle?pin=${appliance.pin}';
    try {
      await http.get(Uri.parse(url)).timeout(const Duration(seconds: 3));
    } catch (e) {
      print("Error toggling appliance: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(controller.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => DeviceSettingsPage(controller: controller),
              ));
            },
            tooltip: "Configure Appliances",
          ),
        ],
      ),
      body: controller.appliances.isEmpty
          ? const Center(
              child: Text("No appliances configured for this device."),
            )
          : ListView.builder(
              itemCount: controller.appliances.length,
              itemBuilder: (context, index) {
                final appliance = controller.appliances[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: SwitchListTile(
                    title: Text(appliance.name),
                    subtitle: Text("GPIO ${appliance.pin}"),
                    value: appliance.state,
                    onChanged: (value) => _toggleApplianceState(appliance),
                    secondary: Icon(
                      Icons.lightbulb_outline,
                      color: appliance.state
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey,
                    ),
                  ),
                );
              },
            ),
    );
  }
}