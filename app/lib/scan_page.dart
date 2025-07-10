import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'wifi_credentials_page.dart';

class DeviceScanPage extends StatefulWidget {
  const DeviceScanPage({super.key});

  @override
  State<DeviceScanPage> createState() => _DeviceScanPageState();
}

class _DeviceScanPageState extends State<DeviceScanPage> {
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  late StreamSubscription<List<ScanResult>> _scanResultsSubscription;

  @override
  void initState() {
    super.initState();
    startScan();
  }

  @override
  void dispose() {
    FlutterBluePlus.stopScan();
    _scanResultsSubscription.cancel();
    super.dispose();
  }

  void startScan() {
    setState(() {
      _isScanning = true;
    });

    _scanResultsSubscription = FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        _scanResults = results.where((r) {
          return r.device.platformName == "Aura-Setup" ||
              r.advertisementData.localName == "Aura-Setup";
        }).toList();
      });
    }, onError: (e) {
      print("Scan Error: $e");
    });

    FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Find Aura Devices'),
      ),
      body: ListView.builder(
        itemCount: _scanResults.length,
        itemBuilder: (context, index) {
          final result = _scanResults[index];
          return ListTile(
            leading: const Icon(Icons.lightbulb_outline),
            title: Text(result.device.platformName),
            subtitle: Text(result.device.remoteId.toString()),
            onTap: () async {
              // Stop scanning and navigate without connecting here
              await FlutterBluePlus.stopScan();
              if (!mounted) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) =>
                      WifiCredentialsPage(device: result.device),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (FlutterBluePlus.isScanningNow) {
            FlutterBluePlus.stopScan();
            setState(() => _isScanning = false);
          } else {
            startScan();
          }
        },
        child: Icon(
          FlutterBluePlus.isScanningNow ? Icons.stop : Icons.search,
        ),
      ),
    );
  }
}