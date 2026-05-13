import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart'; // YENİ EKLENDİ
import '../services/firebase_service.dart'; // YENİ EKLENDİ
import 'dart:math';

class PatientDetailScreen extends StatelessWidget {
  final String patientName;
  final String deviceCode;
  final String patientEmail; // YENİ: Statik liste yerine hastanın e-postasını alıyoruz

  // Firebase servisimizi çağırıyoruz
  final FirebaseService _firebaseService = FirebaseService();

  PatientDetailScreen({
    super.key,
    required this.patientName,
    required this.deviceCode,
    required this.patientEmail,
  });

  @override
  Widget build(BuildContext context) {
    const Color primaryColor = Color(0xFF7FB060); // Yeşil Tema

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      body: Column(
        children: [
          // --- HEADER (GERİ BUTONLU - STATİK KISIM) ---
          Container(
            padding: const EdgeInsets.fromLTRB(10, 50, 20, 30),
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
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        patientName,
                        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        "Device: $deviceCode",
                        style: const TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 40), // Ortalama için boşluk
              ],
            ),
          ),

          // --- İÇERİK (FIREBASE'DEN CANLI DİNLENEN KISIM) ---
          Expanded(
            child: StreamBuilder<DatabaseEvent>(
              stream: _firebaseService.listenToHistory(patientEmail),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: primaryColor));
                }

                // Veritabanından gelen veriyi listeye çevirme
                List<Map<String, dynamic>> historyList = [];
                if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
                  Map data = snapshot.data!.snapshot.value as Map;
                  data.forEach((key, value) {
                    historyList.add(Map<String, dynamic>.from(value));
                  });
                  
                  // Tarihe göre en yeniler en üstte olacak şekilde sırala
                  historyList.sort((a, b) {
                    DateTime dateA = DateTime.parse(a['takenDate']);
                    DateTime dateB = DateTime.parse(b['takenDate']);
                    return dateB.compareTo(dateA);
                  });
                }

                // --- CANLI İSTATİSTİK HESAPLAMA ---
                int taken = historyList.where((h) => h['status'] == 'Taken' || h['status'] == 'Alındı').length;
                int missed = historyList.where((h) => h['status'] == 'Missed').length;
                int skipped = historyList.where((h) => h['status'] == 'Skipped' || h['status'] == 'Atlandı').length;
                int total = taken + missed + skipped;

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      // 1. PASTA GRAFİĞİ KARTI
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))],
                        ),
                        child: Column(
                          children: [
                            const Text("Compliance Summary", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 20),
                            
                            if (total == 0)
                              const SizedBox(
                                height: 200,
                                child: Center(child: Text("No medication data yet", style: TextStyle(color: Colors.grey))),
                              )
                            else
                              Row(
                                children: [
                                  // GRAFİK
                                  Expanded(
                                    flex: 3,
                                    child: SizedBox(
                                      height: 160,
                                      child: CustomPaint(
                                        painter: PieChartPainter(
                                          taken: taken, 
                                          missed: missed, 
                                          skipped: skipped,
                                          total: total
                                        ),
                                        child: Center(
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text("%${((taken/total)*100).toInt()}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24)),
                                              const Text("Success", style: TextStyle(fontSize: 10, color: Colors.grey)),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  // LEGEND (Açıklama)
                                  Expanded(
                                    flex: 2,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _buildLegendItem(Colors.green, "Taken", "$taken"),
                                        const SizedBox(height: 10),
                                        _buildLegendItem(Colors.red, "Missed", "$missed"),
                                        const SizedBox(height: 10),
                                        _buildLegendItem(Colors.orange, "Skipped", "$skipped"),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // 2. DETAYLI LİSTE BAŞLIĞI
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text("Action History", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                      ),
                      const SizedBox(height: 10),

                      // 3. LİSTE
                      if (historyList.isEmpty)
                         const Padding(
                           padding: EdgeInsets.only(top: 20),
                           child: Text("No history found to display.", style: TextStyle(color: Colors.grey)),
                         )
                      else
                        ...historyList.map((item) {
                          final takenDate = DateTime.parse(item['takenDate']);
                          final formattedDate = "${takenDate.day}.${takenDate.month.toString().padLeft(2,'0')}.${takenDate.year} ${takenDate.hour}:${takenDate.minute.toString().padLeft(2, '0')}";
                          
                          bool isSuccess = item['status'] == 'Taken' || item['status'] == 'Alındı';
                          Color statusColor = isSuccess ? Colors.green : (item['status'] == 'Missed' ? Colors.red : Colors.orange);
                          IconData statusIcon = isSuccess ? Icons.check : (item['status'] == 'Missed' ? Icons.warning : Icons.not_interested);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(15),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border(left: BorderSide(color: statusColor, width: 4)),
                            ),
                            child: Row(
                              children: [
                                Icon(statusIcon, color: statusColor),
                                const SizedBox(width: 15),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                                      Text(formattedDate, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                    ],
                                  ),
                                ),
                                Text(item['status'] == 'Missed' ? 'Missed' : (isSuccess ? 'Taken' : 'Skipped'), 
                                  style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12)),
                              ],
                            ),
                          );
                        }), // .toList() yapmamıza gerek kalmadı, spread operator (...) hallediyor
                      
                      const SizedBox(height: 30),
                    ],
                  ),
                );
              }
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label, String value) {
    return Row(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        )
      ],
    );
  }
}

// --- PASTA GRAFİĞİ RESSAMI (CustomPainter) ---
class PieChartPainter extends CustomPainter {
  final int taken;
  final int missed;
  final int skipped;
  final int total;

  PieChartPainter({required this.taken, required this.missed, required this.skipped, required this.total});

  @override
  void paint(Canvas canvas, Size size) {
    Offset center = Offset(size.width / 2, size.height / 2);
    double radius = min(size.width / 2, size.height / 2);
    double strokeWidth = 20.0; // Halkanın kalınlığı

    Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    double startAngle = -pi / 2; // Saat 12 yönünden başla

    // 1. Alınan (Yeşil)
    if (taken > 0) {
      double sweepAngle = (taken / total) * 2 * pi;
      paint.color = Colors.green;
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius - strokeWidth/2), startAngle, sweepAngle, false, paint);
      startAngle += sweepAngle;
    }

    // 2. Kaçırılan (Kırmızı)
    if (missed > 0) {
      double sweepAngle = (missed / total) * 2 * pi;
      paint.color = Colors.red;
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius - strokeWidth/2), startAngle, sweepAngle, false, paint);
      startAngle += sweepAngle;
    }

    // 3. Atlanan (Turuncu)
    if (skipped > 0) {
      double sweepAngle = (skipped / total) * 2 * pi;
      paint.color = Colors.orange;
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius - strokeWidth/2), startAngle, sweepAngle, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}