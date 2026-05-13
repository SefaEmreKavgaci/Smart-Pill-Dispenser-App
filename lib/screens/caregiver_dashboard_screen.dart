import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../services/firebase_service.dart';
import 'patient_detail_screen.dart'; 

class CaregiverDashboardScreen extends StatelessWidget {
  final String currentUserEmail; // Bakıcının kendi e-postası
  final FirebaseService _firebaseService = FirebaseService();

  CaregiverDashboardScreen({super.key, required this.currentUserEmail});

  @override
  Widget build(BuildContext context) {
    const Color primaryColor = Color(0xFF7FB060); // Yeşil Tema (Bakıcı)
    
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      body: Column(
        children: [
          // --- HEADER ---
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.health_and_safety, color: Colors.white, size: 28),
                    SizedBox(width: 10),
                    Text(
                      "Caregiver Dashboard",
                      style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                SizedBox(height: 5),
                Text(
                  "Click on the patient card for details",
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),

          // --- İÇERİK: HASTA LİSTESİ (CANLI YAYIN) ---
          Expanded(
            child: StreamBuilder<DatabaseEvent>(
              stream: _firebaseService.listenToCaregiverPatients(currentUserEmail),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: primaryColor));
                }
                
                if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.person_add_disabled, size: 70, color: Colors.grey[300]),
                        const SizedBox(height: 20),
                        Text("No patients in your list.", style: TextStyle(color: Colors.grey[600], fontSize: 18)),
                      ],
                    ),
                  );
                }

                // Bakıcının hastalarının e-posta listesini alıyoruz
                Map patientsData = snapshot.data!.snapshot.value as Map;
                List<String> patientEmails = patientsData.keys.map((e) => e.toString()).toList();

                return ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: patientEmails.length,
                  itemBuilder: (context, index) {
                    String patientEmail = patientEmails[index];
                    
                    // Her bir hasta için ayrı bir akıllı kart oluşturuyoruz
                    return PatientSummaryCard(
                      patientEmail: patientEmail, 
                      firebaseService: _firebaseService, 
                      themeColor: primaryColor
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

// --- HER BİR HASTA İÇİN KENDİNİ GÜNCELLEYEN AKILLI KART ---
class PatientSummaryCard extends StatelessWidget {
  final String patientEmail;
  final FirebaseService firebaseService;
  final Color themeColor;

  const PatientSummaryCard({
    super.key, 
    required this.patientEmail, 
    required this.firebaseService, 
    required this.themeColor
  });

  @override
  Widget build(BuildContext context) {
    // 1. Hastanın profil bilgilerini (İsim, Cihaz Kodu) bir kez çekiyoruz
    return FutureBuilder<Map<String, dynamic>?>(
      future: firebaseService.getUserProfile(patientEmail),
      builder: (context, profileSnapshot) {
        if (!profileSnapshot.hasData) {
          return const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()));
        }

        var patientProfile = profileSnapshot.data!;
        String patientName = "${patientProfile['name']} ${patientProfile['surname']}";
        String deviceCode = patientProfile['deviceCode'] ?? "Unknown";

        // 2. Hastanın ESP32'den gelen ilaç geçmişini CANLI dinliyoruz
        return StreamBuilder<DatabaseEvent>(
          stream: firebaseService.listenToHistory(patientEmail),
          builder: (context, historySnapshot) {
            List<Map<String, dynamic>> patientHistory = [];
            
            if (historySnapshot.hasData && historySnapshot.data!.snapshot.value != null) {
              Map data = historySnapshot.data!.snapshot.value as Map;
              data.forEach((key, value) {
                patientHistory.add(Map<String, dynamic>.from(value));
              });
              
              // Tarihe göre sırala (En son içilen en üstte)
              patientHistory.sort((a, b) {
                return DateTime.parse(b['takenDate']).compareTo(DateTime.parse(a['takenDate']));
              });
            }

            int missedCount = patientHistory.where((h) => h['status'] == 'Missed').length;
            int takenCount = patientHistory.where((h) => h['status'] == 'Taken' || h['status'] == 'Alındı').length;
            bool hasAlert = missedCount > 0;

            return GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PatientDetailScreen(
                      patientName: patientName,
                      deviceCode: deviceCode,
                      patientEmail: patientEmail, // PatientDetailScreen'e e-posta gönderiyoruz
                    ),
                  ),
                );
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5)),
                  ],
                ),
                child: Column(
                  children: [
                    // Başlık
                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: hasAlert ? Colors.red.withOpacity(0.1) : themeColor.withOpacity(0.1),
                        borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: hasAlert ? Colors.red : themeColor,
                            child: const Icon(Icons.person, color: Colors.white),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  patientName,
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  "Device: $deviceCode",
                                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                        ],
                      ),
                    ),

                    // Özet İstatistikler
                    Padding(
                      padding: const EdgeInsets.all(15),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStatItem(Icons.check_circle, "Taken", "$takenCount", Colors.green),
                          _buildStatItem(Icons.warning, "Missed", "$missedCount", Colors.red),
                          _buildStatItem(
                            Icons.timelapse, 
                            "Last Action", 
                            patientHistory.isNotEmpty 
                              ? "${DateTime.parse(patientHistory.first['takenDate']).hour.toString().padLeft(2, '0')}:${DateTime.parse(patientHistory.first['takenDate']).minute.toString().padLeft(2, '0')}" 
                              : "-", 
                            Colors.blueGrey
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatItem(IconData icon, String label, String value, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 5),
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }
}