import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ManageRoomsPage extends StatefulWidget {
  const ManageRoomsPage({super.key});

  @override
  State<ManageRoomsPage> createState() => _ManageRoomsPageState();
}

class _ManageRoomsPageState extends State<ManageRoomsPage> {
  late final CollectionReference _roomsRef;
  final _roomNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final userId = FirebaseAuth.instance.currentUser!.uid;
    _roomsRef = FirebaseFirestore.instance.collection('users').doc(userId).collection('rooms');
  }

  void _addRoom() {
    if (_roomNameController.text.isNotEmpty) {
      _roomsRef.add({'name': _roomNameController.text});
      _roomNameController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Manage Rooms")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _roomNameController,
                    decoration: const InputDecoration(labelText: "New Room Name"),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _addRoom,
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _roomsRef.snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final rooms = snapshot.data!.docs;
                return ListView.builder(
                  itemCount: rooms.length,
                  itemBuilder: (context, index) {
                    final room = rooms[index];
                    return ListTile(
                      title: Text(room['name']),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => room.reference.delete(),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}