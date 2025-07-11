import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'firebase_options.dart';
import 'scan_page.dart';
import 'settings_page.dart';
import 'device_settings_page.dart';
import 'manage_rooms_page.dart';


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

// --- Auth Wrapper (Decides which page to show) ---
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

// --- Login Page ---
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
      if (googleUser == null) { // User cancelled the sign-in
          if(mounted) setState(() => _isLoading = false);
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
      if(mounted) setState(() => _isLoading = false);
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

// --- Data Models ---
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
  final String id; // MAC Address
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
      parsedAppliances.sort((a,b) => a.pin.compareTo(b.pin));
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

class Room {
  final String id;
  final String name;
  Room({required this.id, required this.name});
}

// --- HomePage with Functional Room Tabs ---
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final DatabaseReference _devicesRef = FirebaseDatabase.instance.ref('devices');
  late final CollectionReference _roomsRef;
  String? _selectedRoomId;

  @override
  void initState() {
    super.initState();
    final userId = FirebaseAuth.instance.currentUser!.uid;
    _roomsRef = FirebaseFirestore.instance.collection('users').doc(userId).collection('rooms');
  }

  void _showApplianceControls(AuraController controller) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter modalState) {
            final controllerStream = _devicesRef.child(controller.id).onValue;
            return StreamBuilder<DatabaseEvent>(
              stream: controllerStream,
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data?.snapshot.value == null) {
                  return const Center(child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: CircularProgressIndicator(),
                  ));
                }
                final updatedController = AuraController.fromFirebase(
                    snapshot.data!.snapshot.key!,
                    snapshot.data!.snapshot.value as Map<dynamic, dynamic>);

                return Container(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(updatedController.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      const Divider(height: 24),
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          children: updatedController.appliances.map((appliance) {
                            return SwitchListTile(
                              title: Text(appliance.name),
                              subtitle: Text("GPIO ${appliance.pin}"),
                              value: appliance.state,
                              onChanged: (value) {
                                final dbRef = FirebaseDatabase.instance.ref('devices/${updatedController.id}/appliances/${appliance.pin}/state');
                                dbRef.set(value ? "ON" : "OFF");
                              },
                              secondary: Icon(Icons.lightbulb_outline, color: appliance.state ? Colors.amber.shade700 : Colors.grey),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
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
                Text('Hi, ${user?.displayName ?? 'Aura User'} 👋', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                CircleAvatar(
                  backgroundImage: user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
                  child: user?.photoURL == null ? const Icon(Icons.person) : null,
                  radius: 20,
                )
              ],
            ),
            const SizedBox(height: 20),
            // --- DYNAMIC ROOM TABS ---
            SizedBox(
              height: 40,
              child: StreamBuilder<QuerySnapshot>(
                stream: _roomsRef.orderBy('name').snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  final rooms = snapshot.data!.docs.map((doc) => Room(id: doc.id, name: doc['name'])).toList();
                  
                  // Set default selected room if not already set
                  if (_selectedRoomId == null && rooms.isNotEmpty) {
                    _selectedRoomId = rooms.first.id;
                  }

                  return ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: rooms.length,
                    separatorBuilder: (context, index) => const SizedBox(width: 16),
                    itemBuilder: (context, index) {
                      final room = rooms[index];
                      final isSelected = _selectedRoomId == room.id;
                      return ChoiceChip(
                        label: Text(room.name),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            _selectedRoomId = selected ? room.id : null;
                          });
                        },
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            // --- FILTERED DEVICE GRID ---
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
                  List<AuraController> allControllers = [];
                  data.forEach((key, value) {
                    allControllers.add(AuraController.fromFirebase(key, value));
                  });

                  // We need to filter which controllers to show based on the selected room
                  // This requires another stream from Firestore to get the config
                  return StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('device_configs').where('roomId', isEqualTo: _selectedRoomId).snapshots(),
                    builder: (context, configSnapshot) {
                      if (!configSnapshot.hasData) return const Center(child: CircularProgressIndicator());
                      
                      final configuredControllerIds = configSnapshot.data!.docs.map((doc) => doc.id).toSet();
                      final filteredControllers = allControllers.where((c) => configuredControllerIds.contains(c.id)).toList();

                      if (filteredControllers.isEmpty) {
                        return const Center(child: Text("No devices found in this room."));
                      }

                      return GridView.builder(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 1,
                        ),
                        itemCount: filteredControllers.length,
                        itemBuilder: (context, index) {
                          final controller = filteredControllers[index];
                          final bool isAnyOn = controller.appliances.any((a) => a.state);

                          return InkWell(
                            onTap: () => _showApplianceControls(controller),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              decoration: BoxDecoration(
                                color: isAnyOn ? Colors.black : Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: isAnyOn ? Colors.black : Colors.grey.shade300, width: 1.5),
                              ),
                              child: Stack(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Icon(Icons.developer_board, size: 32, color: isAnyOn ? Colors.white : Colors.black),
                                        const SizedBox(height: 8),
                                        Text(controller.name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isAnyOn ? Colors.white : Colors.black), maxLines: 2, overflow: TextOverflow.ellipsis),
                                        Text("${controller.appliances.length} appliances", style: TextStyle(fontSize: 12, color: isAnyOn ? Colors.white70 : Colors.black54)),
                                      ],
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 4,
                                    right: 4,
                                    child: IconButton(
                                      icon: Icon(Icons.settings_outlined, color: isAnyOn ? Colors.white54 : Colors.black54),
                                      onPressed: () {
                                        Navigator.of(context).push(MaterialPageRoute(
                                          builder: (context) => DeviceSettingsPage(controller: controller),
                                        ));
                                      },
                                    ),
                                  )
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
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
                Navigator.of(context).push(MaterialPageRoute(builder: (context) => const SettingsPage()));
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