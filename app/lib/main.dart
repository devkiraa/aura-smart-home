import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;
import 'firebase_options.dart';
import 'scan_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const AuraApp());
}

class AuraApp extends StatelessWidget {
  const AuraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Aura',
      theme: ThemeData(
        brightness: Brightness.light,
        fontFamily: 'Inter',
        scaffoldBackgroundColor: const Color(0xFFFAFAFA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
        cardColor: Colors.white,
        colorScheme: ColorScheme.fromSwatch().copyWith(secondary: Colors.black),
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return const HomePage();
        }
        return const LoginPage();
      },
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _isLoading = false;

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      final GoogleSignInAuthentication? googleAuth =
          await googleUser?.authentication;
      if (googleAuth != null) {
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        await FirebaseAuth.instance.signInWithCredential(credential);
      }
    } catch (e) {
      print("Google Sign-In Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lightbulb_outline, size: 80, color: Colors.black87),
            const SizedBox(height: 20),
            const Text('Welcome to Aura', style: TextStyle(fontSize: 24)),
            const SizedBox(height: 40),
            if (_isLoading)
              const CircularProgressIndicator()
            else
              ElevatedButton(
                onPressed: _signInWithGoogle,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
                child: const Text('Sign in with Google', style: TextStyle(fontSize: 18)),
              ),
          ],
        ),
      ),
    );
  }
}

class AuraDevice {
  final String id;
  final String ip;
  final bool online;
  bool state;

  AuraDevice({
    required this.id,
    required this.ip,
    required this.online,
    required this.state,
  });

  factory AuraDevice.fromFirebase(String key, Map<dynamic, dynamic> value) {
    return AuraDevice(
      id: key,
      ip: value['ip'] ?? 'N/A',
      online: value['online'] ?? false,
      state: value['state'] == 'ON',
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final DatabaseReference _devicesRef =
      FirebaseDatabase.instance.ref('devices');

  Future<void> _toggleDeviceState(AuraDevice device) async {
    final newState = !device.state;
    final url = 'http://${device.ip}/${newState ? "on" : "off"}';

    try {
      await http.get(Uri.parse(url)).timeout(const Duration(seconds: 2));
    } catch (e) {
      print("Error toggling device: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to contact device.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.only(top: 60, left: 20, right: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Hi Einstein, 👋',
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                CircleAvatar(
                  backgroundImage: AssetImage('assets/avatar.png'),
                  radius: 20,
                )
              ],
            ),
            const SizedBox(height: 20),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Text("Living Room", style: TextStyle(fontWeight: FontWeight.bold)),
                Text("Bedroom", style: TextStyle(color: Colors.grey)),
                Text("Kitchen", style: TextStyle(color: Colors.grey)),
                Text("Dining Room", style: TextStyle(color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: StreamBuilder(
                stream: _devicesRef.onValue,
                builder: (context, AsyncSnapshot<DatabaseEvent> snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data?.snapshot.value == null) {
                    return const Center(child: Text("No devices found. Add one!"));
                  }

                  Map<dynamic, dynamic> data =
                      snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
                  List<AuraDevice> devices = [];
                  data.forEach((key, value) {
                    devices.add(AuraDevice.fromFirebase(key, value));
                  });

                  return GridView.count(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 1,
                    children: devices.map((device) {
                      return Container(
                        decoration: BoxDecoration(
                          color: device.state ? Colors.black : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: device.state ? Colors.black : Colors.grey.shade300,
                            width: 1.5,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.lightbulb,
                                  size: 32,
                                  color: device.state ? Colors.white : Colors.black),
                              const SizedBox(height: 16),
                              Text(
                                "Device ${device.id.substring(9)}",
                                style: TextStyle(
                                  fontSize: 16,
                                  color:
                                      device.state ? Colors.white : Colors.black,
                                ),
                              ),
                              const Spacer(),
                              Switch(
                                value: device.state,
                                onChanged: (_) => _toggleDeviceState(device),
                                activeColor: Colors.white,
                                inactiveThumbColor: Colors.black,
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        color: Colors.white,
        shape: const CircularNotchedRectangle(),
        notchMargin: 8.0,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            IconButton(onPressed: () {}, icon: const Icon(Icons.home)),
            const SizedBox(width: 48),
            IconButton(onPressed: () {}, icon: const Icon(Icons.notifications_none)),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.black,
        child: const Icon(Icons.add),
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => const DeviceScanPage()),
          );
        },
      ),
    );
  }
}
