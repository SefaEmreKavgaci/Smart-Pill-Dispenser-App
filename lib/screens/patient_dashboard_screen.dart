import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../services/firebase_service.dart';
import '../services/esp_service.dart';

class DashboardScreen extends StatefulWidget {
  final String currentUserEmail;
  const DashboardScreen({super.key, required this.currentUserEmail});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  final EspService _espService = EspService();

  String currentUserName = "Loading...";

  // ESP32'den gelen durum verileri
  // Anahtar: "disk_0_slot_3" gibi app formatı, Değer: "pending" | "taken" | "missed"
  Map<String, String> _espStatuses = {};
  bool _isEspConnected = false;
  bool _isFetchingEsp = false;
  bool _isPaired = true; // Varsayılan olarak true yapıp fetch içinde karar verelim

  @override
  void initState() {
    super.initState();
    _loadUserName();
    _fetchEspStatus();
  }

  /// ESP32'den programı çekip durum haritasını günceller.
  Future<void> _fetchEspStatus() async {
    if (_isFetchingEsp) return;
    setState(() => _isFetchingEsp = true);

    // Eşleşme kontrolü
    var userData = await _firebaseService.getUserProfile(widget.currentUserEmail);
    bool paired = userData != null && (userData['deviceCode'] != null || userData['deviceUrl'] != null);

    if (!paired) {
      if (mounted) {
        setState(() {
          _isPaired = false;
          _isEspConnected = false;
          _isFetchingEsp = false;
        });
      }
      return;
    }

    final scheduleList = await _espService.getSchedule();

    if (!mounted) return;

    if (scheduleList == null) {
      // Cihaza ulaşılamadı
      setState(() {
        _isPaired = true;
        _isEspConnected = false;
        _isFetchingEsp = false;
      });
      return;
    }

    // ESP32 slot numarası = uygulama slot numarası (doğrudan eşleme)
    final Map<String, String> statuses = {};
    for (final item in scheduleList) {
      statuses['slot_${item.slot}'] = item.status;
    }

    setState(() {
      _espStatuses = statuses;
      _isPaired = true;
      _isEspConnected = true;
      _isFetchingEsp = false;
    });
  }

  // İsmi Firebase'den bir kere çek
  Future<void> _loadUserName() async {
    var userData = await _firebaseService.getUserProfile(widget.currentUserEmail);
    if (userData != null && mounted) {
      setState(() {
        currentUserName = "${userData['name']} ${userData['surname']}";
      });
    } else {
      setState(() {
        currentUserName = "User";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color primaryColor = const Color(0xFF2E406E);
    final Color accentColor = const Color(0xFF7FB060);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8), 
      appBar: AppBar(
        automaticallyImplyLeading: false, 
        backgroundColor: primaryColor,
        elevation: 0,
        title: Row(
          children: [
            const CircleAvatar(
              backgroundColor: Colors.white24,
              child: Icon(Icons.person, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Welcome", style: TextStyle(color: Colors.white70, fontSize: 12)),
                Text(currentUserName, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
        actions: [
          _isFetchingEsp
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await _fetchEspStatus();
                    if (!mounted) return;
                    messenger.showSnackBar(SnackBar(
                      content: Text(_isEspConnected ? "Device data updated" : "Device is unreachable"),
                      backgroundColor: _isEspConnected ? Colors.green : Colors.red,
                      duration: const Duration(seconds: 2),
                    ));
                  },
                ),
        ],
      ),
      body: Column(
        children: [
          // --- ÜST PANEL (Cihaz Durumu - CANLI YAYIN) ---
          Container(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
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
            child: Column(
                  children: [
                    // WI-FI KARTI (ESP32 bağlantı durumu)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Colors.white.withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: !_isPaired 
                                ? Colors.grey.withOpacity(0.2) 
                                : (_isEspConnected ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2)),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              !_isPaired ? Icons.link_off : (_isEspConnected ? Icons.wifi : Icons.wifi_off),
                              color: !_isPaired ? Colors.grey : (_isEspConnected ? Colors.greenAccent : Colors.redAccent),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Capsule Device", style: TextStyle(color: Colors.white70, fontSize: 10)),
                              Text(
                                !_isPaired ? "Not Paired" : (_isEspConnected ? "Online" : "No Connection"),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 20),

                    // 2. KAPASİTE KARTI (İlaç sayısını dinliyor)
                    StreamBuilder<DatabaseEvent>(
                      stream: _firebaseService.listenToMedicines(widget.currentUserEmail),
                      builder: (context, medSnapshot) {
                        int fullSlots = 0;
                        if (medSnapshot.hasData && medSnapshot.data!.snapshot.value != null) {
                           Map medData = medSnapshot.data!.snapshot.value as Map;
                           fullSlots = medData.keys.where((k) => k.toString().startsWith('slot_')).length;
                        }

                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Box Capacity", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                                  const SizedBox(height: 5),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text("$fullSlots", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: primaryColor)),
                                      const SizedBox(width: 5),
                                      Text("/ 14", style: TextStyle(fontSize: 18, color: Colors.grey[500], fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                  const SizedBox(height: 5),
                                  Text("Filled Compartments", style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 12)),
                                ],
                              ),
                              SizedBox(
                                height: 60,
                                width: 60,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    CircularProgressIndicator(
                                      value: fullSlots / 14,
                                      backgroundColor: Colors.grey[200],
                                      color: accentColor,
                                      strokeWidth: 8,
                                    ),
                                    Icon(Icons.inbox, color: primaryColor)
                                  ],
                                ),
                              )
                            ],
                          ),
                        );
                      }
                    ),
                  ],
                ),
          ),

          // --- LİSTE BAŞLIĞI ---
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
            child: Row(
              children: [
                Text(
                  'Upcoming Doses',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryColor),
                ),
                const Spacer(),
                Icon(Icons.sort, color: Colors.grey[400], size: 20)
              ],
            ),
          ),

          // --- İLAÇ LİSTESİ (CANLI YAYIN) ---
          Expanded(
            child: StreamBuilder<DatabaseEvent>(
              stream: _firebaseService.listenToMedicines(widget.currentUserEmail),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.grey.shade200, blurRadius: 10)]),
                          child: Icon(Icons.event_busy, size: 50, color: Colors.grey[300]),
                        ),
                        const SizedBox(height: 15),
                        Text("No scheduled medications.", style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.bold)),
                      ],
                    ),
                  );
                }

                Map data = snapshot.data!.snapshot.value as Map;
                List<Map<String, dynamic>> allMedicines = [];

                data.forEach((key, value) {
                  if (key.toString().startsWith('slot_')) {
                    var medMap = Map<String, dynamic>.from(value);
                    medMap['appKey'] = key.toString(); // status lookup için
                    if (medMap['date'] == null) {
                      final now = DateTime.now();
                      medMap['date'] = "${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}";
                    }
                    allMedicines.add(medMap);
                  }
                });

                // Tarih ve saate göre sırala
                allMedicines.sort((a, b) {
                  String dateTimeA = "${a['date']} ${a['time']}";
                  String dateTimeB = "${b['date']} ${b['time']}";
                  return dateTimeA.compareTo(dateTimeB);
                });

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: allMedicines.length,
                  itemBuilder: (context, index) {
                    final medicine = allMedicines[index];
                    String readableDate = medicine['date'];
                    if(medicine['date'].toString().contains('-')) {
                       List<String> dateParts = medicine['date'].toString().split('-');
                       readableDate = "${dateParts[2]}.${dateParts[1]}.${dateParts[0]}";
                    }

                    final String appKey = medicine['appKey'] ?? '';
                    final int slotNum = int.tryParse(appKey.replaceFirst('slot_', '')) ?? 0;
                    final String location = "Compartment $slotNum";
                    final String espStatus = _espStatuses[appKey] ?? 'pending';
                    final statusInfo = _statusStyle(espStatus);

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
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: primaryColor.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.medication, color: primaryColor),
                        ),
                        title: Text(medicine['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Row(children: [Icon(Icons.location_on, size: 12, color: Colors.grey[400]), const SizedBox(width: 4), Text(location, style: TextStyle(color: Colors.grey[600], fontSize: 12))]),
                            const SizedBox(height: 2),
                            Row(children: [Icon(Icons.calendar_today, size: 12, color: Colors.grey[400]), const SizedBox(width: 4), Text(readableDate, style: TextStyle(color: Colors.grey[600], fontSize: 12))]),
                          ],
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(color: accentColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                              child: Text(medicine['time'], style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: accentColor)),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: statusInfo.$1.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
                              child: Text(statusInfo.$2, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusInfo.$1)),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              }
            ),
          ),
        ],
      ),
    );
  }
  
  /// ESP32 durum stringine göre renk ve Türkçe etiket döner.
  (Color, String) _statusStyle(String status) {
    switch (status) {
      case 'taken':
        return (Colors.green, 'Taken');
      case 'missed':
        return (Colors.red, 'Missed');
      case 'pending':
      default:
        return (Colors.orange, 'Pending');
    }
  }
}