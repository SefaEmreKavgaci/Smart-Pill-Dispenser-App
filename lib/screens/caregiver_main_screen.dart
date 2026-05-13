import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart'; // YENİ EKLENDİ
import '../services/firebase_service.dart'; // YENİ EKLENDİ
import 'caregiver_dashboard_screen.dart';
import 'login_screen.dart';

class CaregiverMainScreen extends StatefulWidget {
  final String currentUserEmail;
  const CaregiverMainScreen({super.key, required this.currentUserEmail});

  @override
  State<CaregiverMainScreen> createState() => _CaregiverMainScreenState();
}

class _CaregiverMainScreenState extends State<CaregiverMainScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    // Sayfaları oluştururken bakıcının e-postasını gönderiyoruz
    final List<Widget> pages = [
      CaregiverDashboardScreen(currentUserEmail: widget.currentUserEmail), 
      PatientsListScreen(currentUserEmail: widget.currentUserEmail), 
      const CaregiverProfileScreen(), 
    ];

    const Color secondaryColor = Color(0xFF7FB060); 

    return Scaffold(
      body: pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: secondaryColor,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Patients'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

// --- HASTA LİSTESİ VE EKLEME EKRANI (FIREBASE UYUMLU) ---
class PatientsListScreen extends StatefulWidget {
  final String currentUserEmail;
  const PatientsListScreen({super.key, required this.currentUserEmail});

  @override
  State<PatientsListScreen> createState() => _PatientsListScreenState();
}

class _PatientsListScreenState extends State<PatientsListScreen> {
  final FirebaseService _firebaseService = FirebaseService();

  void _showAddPatientDialog() {
    TextEditingController codeController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Add Patient"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Enter your patient's 6-digit ID:"),
            const SizedBox(height: 10),
            TextField(
              controller: codeController,
              decoration: const InputDecoration(
                hintText: "e.g. 123456",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.qr_code),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              String code = codeController.text.trim();
              Navigator.pop(context); // Dialogu kapat
              if (code.isNotEmpty) {
                await _findAndAddPatient(code);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7FB060), foregroundColor: Colors.white),
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }

  Future<void> _findAndAddPatient(String code) async {
    // 1. Hasta ID'sine göre hastanın e-postasını bul
    String? patientEmail = await _firebaseService.findPatientByPatientId(code);

    if (patientEmail != null) {
      // 2. Bulunan hastayı bakıcının listesine ekle
      bool success = await _firebaseService.addPatientToCaregiver(widget.currentUserEmail, patientEmail);
      
      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Patient added successfully!"), backgroundColor: Colors.green));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("This patient is already in your list."), backgroundColor: Colors.orange));
      }
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No patient found with this ID."), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryColor = Color(0xFF7FB060);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      body: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 60, 20, 30),
            decoration: BoxDecoration(
              color: primaryColor,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(30),
                bottomRight: Radius.circular(30),
              ),
              boxShadow: [
                BoxShadow(color: primaryColor.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 5))
              ]
            ),
            width: double.infinity,
            child: const Column(
              children: [
                Text(
                  "My Patients",
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 5),
                Text(
                  "People you are tracking",
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),

          // Liste (Canlı Yayın - StreamBuilder)
          Expanded(
            child: StreamBuilder<DatabaseEvent>(
              stream: _firebaseService.listenToCaregiverPatients(widget.currentUserEmail),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: primaryColor));
                }

                if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.person_add_alt_1, size: 60, color: Colors.grey),
                        SizedBox(height: 10),
                        Text("You haven't added any patients yet."),
                      ],
                    ),
                  );
                }

                // Hastaların e-posta listesini al
                Map patientsData = snapshot.data!.snapshot.value as Map;
                List<String> patientEmails = patientsData.keys.map((e) => e.toString()).toList();

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: patientEmails.length,
                  itemBuilder: (context, index) {
                    String patientEmail = patientEmails[index];

                    // Her bir hastanın profil bilgilerini (isim, cihaz kodu) çekmek için FutureBuilder
                    return FutureBuilder<Map<String, dynamic>?>(
                      future: _firebaseService.getUserProfile(patientEmail),
                      builder: (context, profileSnapshot) {
                        if (!profileSnapshot.hasData) {
                          return const Card(child: ListTile(title: Text("Loading...")));
                        }

                        var patientProfile = profileSnapshot.data!;
                        String patientName = "${patientProfile['name']} ${patientProfile['surname']}";
                        String patientId = patientProfile['patientId'] ?? "Unknown";

                        return Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: primaryColor.withOpacity(0.2), 
                              child: const Icon(Icons.person, color: primaryColor)
                            ),
                            title: Text(patientName, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text("Patient ID: $patientId"),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              onPressed: () {
                                _firebaseService.removePatientFromCaregiver(widget.currentUserEmail, patientEmail);
                              },
                            ),
                          ),
                        );
                      }
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddPatientDialog,
        backgroundColor: primaryColor,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

// --- PROFİL VE ÇIKIŞ EKRANI ---
class CaregiverProfileScreen extends StatelessWidget {
  const CaregiverProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const Color primaryColor = Color(0xFF7FB060);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 60, 20, 30),
            decoration: BoxDecoration(
              color: primaryColor,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(30),
                bottomRight: Radius.circular(30),
              ),
              boxShadow: [
                BoxShadow(color: primaryColor.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 5))
              ]
            ),
            width: double.infinity,
            child: const Center(
              child: Text(
                "Settings",
                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                  child: ListTile(
                    leading: const Icon(Icons.logout, color: Colors.red),
                    title: const Text("Log Out", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                    onTap: () {
                       Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(builder: (context) => const LoginScreen()),
                          (route) => false,
                        );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}