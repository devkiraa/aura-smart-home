import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;
import 'firebase_options.dart';
import 'scan_page.dart';
import 'settings_page.dart';
import 'device_settings_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const AuraApp());
}

// --- Root App Widget ---
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
      routes: {
        '/login': (context) => const LoginPage(),
      },
    );
  }
}

// --- Auth Wrapper (Unchanged) ---
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasData) {
          return const HomePage();
        }
        return const LoginPage();
      },
    );
  }
}

// --- Login Page (Unchanged) ---
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
      if (googleUser == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      final GoogleSignInAuthentication? googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth?.accessToken,
        idToken: googleAuth?.idToken,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
    } catch (e) {
      print("Google Sign-In Error: $e");
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
            const Text('Welcome to Aura', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 40),
            if (_isLoading)
              const CircularProgressIndicator(color: Colors.black)
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

// --- Data Models (Unchanged) ---
class Appliance {
  final int pin;
  final String name;
  bool state;
  Appliance({required this.pin, required this.name, required this.state});
  factory Appliance.fromFirebase(String key, Map<dynamic, dynamic> value) {
    return Appliance(
      pin: int.parse(key),
      name: value['name'] ?? 'Unnamed Appliance',
      state: value['state'] == 'ON',
    );
  }
}

class AuraController {
  final String id;
  final String ip;
  final String name;
  final String version;
  final List<Appliance> appliances;
  AuraController({required this.id, required this.ip, required this.name, required this.version, required this.appliances});
  factory AuraController.fromFirebase(String key, Map<dynamic, dynamic> value) {
    List<Appliance> parsedAppliances = [];
    if (value['appliances'] != null) {
      final appliancesMap = value['appliances'] as Map<dynamic, dynamic>;
      appliancesMap.forEach((pin, appValue) {
        parsedAppliances.add(Appliance.fromFirebase(pin, appValue));
      });
    }
    return AuraController(
      id: key,
      ip: value['ip'] ?? 'N/A',
      name: value['name'] ?? 'Aura Controller',
      version: value['version'] ?? '0.0',
      appliances: parsedAppliances,
    );
  }
}

// --- HomePage with restored GridView UI ---
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final DatabaseReference _devicesRef = FirebaseDatabase.instance.ref('devices');

  Future<void> _toggleDeviceState(AuraController controller) async {
    // This switch now controls the FIRST appliance in the list.
    if (controller.appliances.isEmpty) return;
    
    final primaryAppliance = controller.appliances.first;
    final url = 'http://${controller.ip}/toggle?pin=${primaryAppliance.pin}';

    try {
      await http.get(Uri.parse(url)).timeout(const Duration(seconds: 2));
    } catch (e) {
      print("Error toggling device: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to contact device.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.only(top: 60, left: 20, right: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Hi, ${user?.displayName ?? 'Aura User'} 👋',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                CircleAvatar(
                  backgroundImage: user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
                  child: user?.photoURL == null ? const Icon(Icons.person) : null,
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

                  Map<dynamic, dynamic> data = snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
                  List<AuraController> controllers = [];
                  data.forEach((key, value) {
                    controllers.add(AuraController.fromFirebase(key, value));
                  });

                  return GridView.count(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 1,
                    children: controllers.map((controller) {
                      // The card's state is based on the first appliance, or OFF if none are configured.
                      final bool isCardOn = controller.appliances.isNotEmpty ? controller.appliances.first.state : false;
                      final String cardTitle = controller.appliances.isNotEmpty ? controller.appliances.first.name : controller.name;

                      return Container(
                        decoration: BoxDecoration(
                          color: isCardOn ? Colors.black : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isCardOn ? Colors.black : Colors.grey.shade300,
                            width: 1.5,
                          ),
                        ),
                        child: Stack(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.lightbulb, size: 32, color: isCardOn ? Colors.white : Colors.black),
                                  const SizedBox(height: 8),
                                  Text(
                                    cardTitle,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: isCardOn ? Colors.white : Colors.black,
                                    ),
                                  ),
                                  Text(
                                    "v${controller.version}",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isCardOn ? Colors.white70 : Colors.black54,
                                    ),
                                  ),
                                  const Spacer(),
                                  Switch(
                                    value: isCardOn,
                                    onChanged: (_) => _toggleDeviceState(controller),
                                    activeColor: Colors.white,
                                    activeTrackColor: Colors.white.withOpacity(0.5),
                                    inactiveThumbColor: Colors.black,
                                    inactiveTrackColor: Colors.black12,
                                  ),
                                ],
                              ),
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: IconButton(
                                icon: Icon(
                                  Icons.settings,
                                  color: isCardOn ? Colors.white54 : Colors.black54,
                                ),
                                onPressed: () {
                                  Navigator.of(context).push(MaterialPageRoute(
                                    builder: (context) => DeviceSettingsPage(controller: controller),
                                  ));
                                },
                              ),
                            ),
                          ],
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
            IconButton(onPressed: () {}, icon: const Icon(Icons.home_outlined)),
            const SizedBox(width: 48),
            IconButton(
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (context) => const SettingsPage(),
                ));
              },
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => const DeviceScanPage()),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}