import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:wifi_scan/wifi_scan.dart';

class WifiCredentialsPage extends StatefulWidget {
  final BluetoothDevice device;
  const WifiCredentialsPage({super.key, required this.device});

  @override
  State<WifiCredentialsPage> createState() => _WifiCredentialsPageState();
}

class _WifiCredentialsPageState extends State<WifiCredentialsPage> {
  List<WiFiAccessPoint> _results = [];
  bool _isScanning = true;
  bool _isSending = false;
  String? _selectedSsid;
  final _passwordController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // UUIDs from our new ESP32 Firmware
  final String serviceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  final String configCharacteristicUuid = "beb5483e-36e1-4688-b7f5-ea07361b26a8";

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  // _startScan and _getScannedResults remain unchanged
  Future<void> _startScan() async {
    setState(() => _isScanning = true);
    final canScan = await WiFiScan.instance.canStartScan(askPermissions: true);
    if (canScan != CanStartScan.yes) {
      if (mounted) {
        setState(() => _isScanning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Cannot scan for Wi-Fi: $canScan")),
        );
      }
      return;
    }
    await WiFiScan.instance.startScan();
    if (mounted) _getScannedResults();
  }

  Future<void> _getScannedResults() async {
    final canGetResults =
        await WiFiScan.instance.canGetScannedResults(askPermissions: false);
    if (canGetResults != CanGetScannedResults.yes) {
      if (mounted) setState(() => _isScanning = false);
      return;
    }
    final results = await WiFiScan.instance.getScannedResults();
    if (mounted) {
      setState(() {
        _results = results;
        _isScanning = false;
      });
    }
  }


  Future<void> _sendCredentials() async {
    if (_selectedSsid == null || !_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _isSending = true);

    try {
      await widget.device.connect();
      List<BluetoothService> services = await widget.device.discoverServices();
      final service = services.firstWhere(
        (s) => s.uuid.toString().toLowerCase() == serviceUuid,
      );

      // Find our single config characteristic
      final configChar = service.characteristics.firstWhere(
        (c) => c.uuid.toString().toLowerCase() == configCharacteristicUuid,
      );

      // Create the JSON payload
      final payload = {
        "ssid": _selectedSsid!,
        "pass": _passwordController.text,
      };
      final jsonString = jsonEncode(payload);

      // Write the JSON string to the characteristic
      await configChar.write(utf8.encode(jsonString));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Credentials sent! Device is restarting.')),
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      print("Error sending credentials: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      await widget.device.disconnect();
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The build method is unchanged
    return Scaffold(
      appBar: AppBar(
        title: Text("Setup ${widget.device.platformName}"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isScanning ? null : _startScan,
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (_isScanning)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_results.isEmpty)
              const Expanded(
                  child: Center(
                      child: Text(
                          "No Wi-Fi networks found.\nPress refresh to try again.",
                          textAlign: TextAlign.center)))
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    final result = _results[index];
                    if (result.ssid.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return Card(
                      color: _selectedSsid == result.ssid
                          ? Colors.blue.withOpacity(0.3)
                          : null,
                      child: ListTile(
                        title: Text(result.ssid),
                        leading: const Icon(Icons.wifi),
                        trailing: Text("${result.level} dBm"),
                        onTap: () {
                          setState(() {
                            _selectedSsid = result.ssid;
                          });
                        },
                      ),
                    );
                  },
                ),
              ),
            if (_selectedSsid != null) ...[
              const Divider(),
              const SizedBox(height: 10),
              Text("Selected Network: $_selectedSsid",
                  style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 10),
              Form(
                key: _formKey,
                child: TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => (value?.isEmpty ?? true)
                      ? 'Password cannot be empty'
                      : null,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isSending ? null : _sendCredentials,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: _isSending
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Connect'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}