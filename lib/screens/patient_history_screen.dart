import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart'; // YENİ EKLENDİ
import '../services/firebase_service.dart'; // YENİ EKLENDİ

class PatientHistoryScreen extends StatelessWidget {
  final String currentUserEmail; // YENİ: Firebase'de doğru kişiyi bulmak için e-posta şart
  
  // Firebase servisimizi çağırıyoruz
  final FirebaseService _firebaseService = FirebaseService();

  PatientHistoryScreen({super.key, required this.currentUserEmail});

  @override
  Widget build(BuildContext context) {
    const Color primaryColor = Color(0xFF2E406E);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8), // Genel arka plan rengi
      body: Column(
        children: [
          // --- ÖZEL TASARIM HEADER ---
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
                  "Action History",
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 5),
                Text(
                  "Taken and missed medications",
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),

          // --- LİSTE (CANLI YAYIN) ---
          Expanded(
            child: StreamBuilder<DatabaseEvent>(
              stream: _firebaseService.listenToHistory(currentUserEmail),
              builder: (context, snapshot) {
                // Yüklenme durumu
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: primaryColor));
                }

                // Veri yoksa gösterilecek ekran
                if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.history, size: 60, color: Colors.grey),
                        SizedBox(height: 10),
                        Text("No history record yet.", style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  );
                }

                // Veritabanından gelen karmaşık veriyi düzgün bir listeye çeviriyoruz
                Map data = snapshot.data!.snapshot.value as Map;
                List<Map<String, dynamic>> historyList = [];
                
                data.forEach((key, value) {
                  historyList.add(Map<String, dynamic>.from(value));
                });

                // Verileri tersten sırala (En son alınan en üstte)
                historyList.sort((a, b) {
                  return DateTime.parse(b['takenDate']).compareTo(DateTime.parse(a['takenDate']));
                });

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: historyList.length,
                  itemBuilder: (context, index) {
                    final item = historyList[index];
                    final takenDate = DateTime.parse(item['takenDate']);
                    final formattedDate = "${takenDate.day.toString().padLeft(2, '0')}.${takenDate.month.toString().padLeft(2, '0')}.${takenDate.year} - ${takenDate.hour.toString().padLeft(2, '0')}:${takenDate.minute.toString().padLeft(2, '0')}";
                    
                    bool isSuccess = item['status'] == 'Taken' || item['status'] == 'Taken';
                    Color statusColor = isSuccess ? Colors.green : (item['status'] == 'Missed' ? Colors.red : Colors.orange);
                    IconData statusIcon = isSuccess ? Icons.check : (item['status'] == 'Missed' ? Icons.close : Icons.not_interested);
                    String statusText = isSuccess ? "Taken" : (item['status'] == 'Missed' ? "Missed" : "Skipped");

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4)),
                        ],
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: CircleAvatar(
                          backgroundColor: statusColor.withOpacity(0.1),
                          child: Icon(statusIcon, color: statusColor),
                        ),
                        title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("Planned: ${item['time']}\nAction: $formattedDate", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              statusText, 
                              style: TextStyle(fontWeight: FontWeight.bold, color: statusColor)
                            ),
                            Text(
                              "Compartment ${item['slot'] ?? '-'}",
                              style: const TextStyle(fontSize: 12, color: Colors.grey)
                            ),
                          ],
                        ),
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