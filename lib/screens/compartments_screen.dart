import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import '../services/firebase_service.dart';
import '../services/esp_service.dart';
import 'dart:math';

class CompartmentsScreen extends StatefulWidget {
  final String currentUserEmail;
  const CompartmentsScreen({super.key, required this.currentUserEmail});

  @override
  State<CompartmentsScreen> createState() => _CompartmentsScreenState();
}

class _CompartmentsScreenState extends State<CompartmentsScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  final EspService _espService = EspService();

  late final DatabaseReference _dbRef = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: 'https://kapsul-db9f7-default-rtdb.europe-west1.firebasedatabase.app',
  ).ref();

  static const int _slotCount = 14;

  String? _pressedSlotKey;
  Map<String, dynamic> _medicines = {};
  String? _deviceCode;

  @override
  void initState() {
    super.initState();
    _loadDeviceCode();
  }

  Future<void> _loadDeviceCode() async {
    final profile = await _firebaseService.getUserProfile(widget.currentUserEmail);
    if (mounted) {
      setState(() => _deviceCode = profile?['deviceCode']);
    }
  }

  String _sanitizeEmail(String email) =>
      email.replaceAll('.', '_').replaceAll('@', '_');

  int get _filledCount =>
      _medicines.keys.where((k) => k.startsWith('slot_')).length;

  /// Tüm ilaçları + yeni ilacı tarihe/saate göre sıralar ve Firebase'e yazar.
  Future<bool> _insertMedicineSorted(Map<String, dynamic> newMed) async {
    final sanitizedEmail = _sanitizeEmail(widget.currentUserEmail);
    final medsRef = _dbRef
        .child('users')
        .child(sanitizedEmail)
        .child('medicines');

    // 1. Firebase'den güncel veriyi doğrudan oku (state değil, gerçek anlık veri)
    final snapshot = await medsRef.get();
    final tempMeds = <Map<String, dynamic>>[];
    if (snapshot.value != null) {
      final raw = Map<String, dynamic>.from(snapshot.value as Map);
      for (final entry in raw.entries) {
        if (!entry.key.startsWith('slot_')) continue;
        tempMeds.add(Map<String, dynamic>.from(entry.value as Map));
      }
    }

    // 2. Yeni ilacı ekle
    tempMeds.add(Map<String, dynamic>.from(newMed));

    // 3. Tarih + saat'e göre sırala
    tempMeds.sort((a, b) {
      final da = DateTime.tryParse('${a['date']}T${a['time']}:00') ?? DateTime(9999);
      final db = DateTime.tryParse('${b['date']}T${b['time']}:00') ?? DateTime(9999);
      return da.compareTo(db);
    });

    // 4. Slot numaralarını güncelle
    for (int i = 0; i < tempMeds.length; i++) {
      tempMeds[i]['slotNumber'] = i + 1;
    }

    // 5. Tüm kompartmanları sil, temiz liste olarak tek seferde yaz
    await medsRef.remove();
    final writes = <String, dynamic>{};
    for (int i = 0; i < tempMeds.length; i++) {
      writes['slot_${i + 1}'] = tempMeds[i];
    }
    await medsRef.set(writes);

    // 6. ESP32'ye tam listeyi tek seferde gönder
    final espPayload = <String, dynamic>{};
    for (int i = 0; i < tempMeds.length; i++) {
      espPayload['slot_${i + 1}'] = tempMeds[i];
    }
    return _espService.syncSchedule(espPayload);
  }

  // ─── FIREBASE SLOT İŞLEMLERİ ───────────────────────────────────────────────

  /// Belirtilen slot numarasını Firebase'den siler, geri kalanları
  /// fresh read ile yeniden numaralandırır ve ESP32'ye tam listeyi gönderir.
  Future<void> _deleteSlot(int slotNumber) async {
    final sanitizedEmail = _sanitizeEmail(widget.currentUserEmail);
    final medsRef = _dbRef
        .child('users')
        .child(sanitizedEmail)
        .child('medicines');

    // 1. Firebase'den güncel listeyi oku
    final snapshot = await medsRef.get();
    final remaining = <Map<String, dynamic>>[];
    if (snapshot.value != null) {
      final raw = Map<String, dynamic>.from(snapshot.value as Map);
      for (final entry in raw.entries) {
        if (!entry.key.startsWith('slot_')) continue;
        final num = int.tryParse(entry.key.split('_')[1]) ?? 0;
        if (num == slotNumber) continue; // silinecek slot atla
        remaining.add(Map<String, dynamic>.from(entry.value as Map));
      }
    }

    // 2. Sırayı koru (date+time), yeniden numaralandır
    remaining.sort((a, b) {
      final da = DateTime.tryParse('${a['date']}T${a['time']}:00') ?? DateTime(9999);
      final db = DateTime.tryParse('${b['date']}T${b['time']}:00') ?? DateTime(9999);
      return da.compareTo(db);
    });
    for (int i = 0; i < remaining.length; i++) {
      remaining[i]['slotNumber'] = i + 1;
    }

    // 3. Tümünü sil, temiz şekilde yaz
    await medsRef.remove();
    if (remaining.isNotEmpty) {
      final writes = <String, dynamic>{};
      for (int i = 0; i < remaining.length; i++) {
        writes['slot_${i + 1}'] = remaining[i];
      }
      await medsRef.set(writes);
    }

    // 4. ESP32'ye güncel listeyi gönder
    final syncMap = <String, dynamic>{};
    for (int i = 0; i < remaining.length; i++) {
      syncMap['slot_${i + 1}'] = remaining[i];
    }
    await _espService.syncSchedule(syncMap);
  }

  /// Slot 1'deki ilacı alınmış olarak işaretler; listeyi _deleteSlot ile günceller.
  Future<void> _takeFromSlot1(Map<String, dynamic> slotData) async {
    final uniqueId = 'slot_1_taken_${DateTime.now().millisecondsSinceEpoch}';
    await _firebaseService.addHistoryRecord(widget.currentUserEmail, uniqueId, {
      'uniqueId': uniqueId,
      'name': slotData['name'],
      'time': slotData['time'],
      'date': slotData['date'],
      'takenDate': DateTime.now().toString(),
      'status': 'Taken',
      'slot': 1,
    });
    // Silme + yeniden sıralama + ESP sync hepsi _deleteSlot'ta
    await _deleteSlot(1);
  }

  // ─── DIALOG'LAR ────────────────────────────────────────────────────────────

  /// Yeni ilaç ekleme dialogu. Merkezdeki + butonuna basınca açılır.
  void _showAddDialog() {
    if (_deviceCode == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Please connect a device from Settings to add medication."),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    if (_filledCount >= _slotCount) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("All compartments are full. Please take a medication first."),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    final nameController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    TimeOfDay selectedTime = TimeOfDay.now();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final dateText =
              "${selectedDate.day.toString().padLeft(2, '0')}.${selectedDate.month.toString().padLeft(2, '0')}.${selectedDate.year}";

          return AlertDialog(
            backgroundColor: Colors.white.withOpacity(0.95),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E406E).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.medication, color: Color(0xFF2E406E), size: 22),
                ),
                const SizedBox(width: 10),
                const Text(
                  "Add New Medication",
                  style: TextStyle(
                      color: Color(0xFF2E406E), fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: "Medication Name",
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none),
                    prefixIcon:
                        const Icon(Icons.medication, color: Color(0xFF2E406E)),
                  ),
                ),
                const SizedBox(height: 15),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime.now(),
                            lastDate:
                                DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) {
                            setDialogState(() => selectedDate = picked);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 15, horizontal: 10),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Date",
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 5),
                              Text(dateText,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF2E406E))),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showTimePicker(
                              context: context, initialTime: selectedTime);
                          if (picked != null) {
                            setDialogState(() => selectedTime = picked);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 15, horizontal: 10),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Time",
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 5),
                              Text(selectedTime.format(context),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF2E406E))),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel",
                    style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (nameController.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text("Please enter a medication name."),
                        backgroundColor: Colors.red));
                    return;
                  }

                  final formattedTime =
                      '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}';
                  final formattedDate =
                      "${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}";

                  // Aynı tarih + saate zaten ilaç var mı?
                  final duplicate = _medicines.values.any((v) =>
                      v['date'] == formattedDate && v['time'] == formattedTime);
                  if (duplicate) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text("A medication is already added for this date and time. Please select a different time."),
                      backgroundColor: Colors.red,
                    ));
                    return;
                  }

                  // Geçmiş veya şimdiki zamana ilaç eklenemez
                  final selectedDateTime = DateTime(
                    selectedDate.year, selectedDate.month, selectedDate.day,
                    selectedTime.hour, selectedTime.minute,
                  );
                  if (!selectedDateTime.isAfter(DateTime.now())) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text("Medication cannot be added for the past or present. Please select a future date/time."),
                      backgroundColor: Colors.red,
                    ));
                    return;
                  }

                  final newData = {
                    'name': nameController.text,
                    'time': formattedTime,
                    'date': formattedDate,
                    'isFull': true,
                  };

                  final synced = await _insertMedicineSorted(newData);

                  if (!context.mounted) return;
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(synced
                        ? "Medication added and sent to the device."
                        : "Medication saved but couldn\\'t be sent to the device. Check device connection."),
                    backgroundColor: synced ? Colors.green : Colors.orange,
                  ));
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E406E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("Save"),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Dolu bir slota dokunulduğunda bilgi + işlem dialogu açar.
  void _showSlotInfoDialog(int slotNumber) {
    final key = 'slot_$slotNumber';
    final raw = _medicines[key];
    if (raw == null) return; // Boş slot — dokunmayı yoksay

    final slotData = Map<String, dynamic>.from(raw as Map);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white.withOpacity(0.95),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: const Color(0xFF2E406E).withOpacity(0.1),
                  shape: BoxShape.circle),
              child: Text(
                "$slotNumber",
                style: const TextStyle(
                    color: Color(0xFF2E406E),
                    fontWeight: FontWeight.bold,
                    fontSize: 18),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                slotData['name'] ?? '',
                style: const TextStyle(
                    color: Color(0xFF2E406E), fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Bilgi satırları
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.access_time, color: Color(0xFF2E406E)),
              title: Text(slotData['time'] ?? '',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text("Time to Take"),
            ),
            if (slotData['date'] != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today,
                    color: Color(0xFF2E406E)),
                title: Text(slotData['date'] ?? ''),
                subtitle: const Text("Date"),
              ),
            const Divider(),

            // --- SLOT 1: İlaç Alındı + Manuel Ver ---
            if (slotNumber == 1) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.check_circle, color: Colors.green),
                  label: const Text("Medication Taken",
                      style: TextStyle(
                          color: Colors.green, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: const BorderSide(color: Colors.green),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    Navigator.pop(context);
                    await _takeFromSlot1(slotData);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text("Medication taken and saved to history."),
                        backgroundColor: Colors.green));
                  },
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.play_circle_outline,
                      color: Color(0xFF2E406E)),
                  label: const Text("Dispense Now (Manual)",
                      style: TextStyle(
                          color: Color(0xFF2E406E),
                          fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: const BorderSide(color: Color(0xFF2E406E)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    // Slot_1 verisini dialog kapanmadan önce al
                    final slot1Data = _medicines['slot_1'] != null
                        ? Map<String, dynamic>.from(_medicines['slot_1'] as Map)
                        : null;
                    Navigator.pop(context);

                    final success = await _espService.dispense(slotNumber: 1);

                    if (!context.mounted) return;

                    if (!success) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text("Device unreachable."),
                        backgroundColor: Colors.red,
                      ));
                      return;
                    }

                    // Dispense başarılı → geçmişe yaz, _deleteSlot ile temizle
                    if (slot1Data != null) {
                      final uniqueId =
                          'slot_1_manual_${DateTime.now().millisecondsSinceEpoch}';
                      await _firebaseService.addHistoryRecord(
                          widget.currentUserEmail, uniqueId, {
                        'uniqueId': uniqueId,
                        'name': slot1Data['name'],
                        'time': slot1Data['time'],
                        'date': slot1Data['date'],
                        'takenDate': DateTime.now().toString(),
                        'status': 'Alındı',
                        'slot': 1,
                      });
                      await _deleteSlot(1);
                    }

                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text("Compartment 1 opened and dispensed."),
                      backgroundColor: Color(0xFF2E406E),
                    ));
                  },
                ),
              ),
              const SizedBox(height: 10),
            ],

            // --- Tüm slotlar: Sil ---
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.delete_forever, color: Colors.white),
                label: const Text("Delete Medication",
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  Navigator.pop(context);
                  await _deleteSlot(slotNumber);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text("Medication deleted."),
                      backgroundColor: Colors.red));
                },
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                const Text("Close", style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  // ─── DOKUNMA HESAPLAMALARI ─────────────────────────────────────────────────

  int? _calculateIndex(Offset localPosition, double radius) {
    final dx = localPosition.dx - radius;
    final dy = localPosition.dy - radius;
    final distance = sqrt(dx * dx + dy * dy);

    if (distance < radius * 0.28 || distance > radius) return null;

    double angle = atan2(dy, dx) + pi / 2;
    if (angle < 0) angle += 2 * pi;

    final sliceAngle = (2 * pi) / _slotCount;
    final index = (angle / sliceAngle).floor();
    return (index >= 0 && index < _slotCount) ? index : null;
  }

  void _onTapDown(TapDownDetails details, double radius) {
    final index = _calculateIndex(details.localPosition, radius);
    if (index != null) setState(() => _pressedSlotKey = "$index");
  }

  void _onTapUp(TapUpDetails details, double radius) {
    final index = _calculateIndex(details.localPosition, radius);
    if (index != null && _pressedSlotKey == "$index") {
      _showSlotInfoDialog(index + 1); // 1-based slot number
    }
    setState(() => _pressedSlotKey = null);
  }

  void _onTapCancel() => setState(() => _pressedSlotKey = null);

  // ─── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    const Color primaryColor = Color(0xFF2E406E);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      body: StreamBuilder<DatabaseEvent>(
        stream: _firebaseService.listenToMedicines(widget.currentUserEmail),
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
            _medicines =
                Map<String, dynamic>.from(snapshot.data!.snapshot.value as Map);
          } else {
            _medicines = {};
          }

          return Column(
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
                    BoxShadow(
                        color: primaryColor.withOpacity(0.4),
                        blurRadius: 10,
                        offset: const Offset(0, 5)),
                  ],
                ),
                width: double.infinity,
                child: Column(
                  children: [
                    const Text(
                      "Box Management",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      "$_filledCount/$_slotCount Compartments Filled",
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ),

              // Disk alanı
              Expanded(
                child: Center(child: _buildPizzaDisk()),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPizzaDisk() {
    const double size = 340;
    const double radius = size / 2;
    const double sliceAngle = (2 * pi) / _slotCount;
    const Color primaryColor = Color(0xFF2E406E);

    return GestureDetector(
      onTapDown: (d) => _onTapDown(d, radius),
      onTapUp: (d) => _onTapUp(d, radius),
      onTapCancel: _onTapCancel,
      child: Container(
        height: size,
        width: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
                color: primaryColor.withOpacity(0.3),
                blurRadius: 30,
                spreadRadius: -5,
                offset: const Offset(0, 15)),
            const BoxShadow(
                color: Colors.white,
                blurRadius: 20,
                spreadRadius: -2,
                offset: Offset(-10, -10)),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Dilimler
            CustomPaint(
              size: const Size(size, size),
              painter: SlicePainter(
                slotCount: _slotCount,
                sliceAngle: sliceAngle,
                pressedSlotKey: _pressedSlotKey,
                medicines: _medicines,
              ),
            ),

            // Slot numaraları
            ...List.generate(_slotCount, (index) {
              final angle =
                  (sliceAngle * index) - (pi / 2) + (sliceAngle / 2);
              const labelRadius = radius * 0.76;
              final isFull = _medicines.containsKey('slot_${index + 1}');

              return Transform.translate(
                offset: Offset(
                    labelRadius * cos(angle), labelRadius * sin(angle)),
                child: Text(
                  "${index + 1}",
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    color: isFull
                        ? Colors.white
                        : primaryColor.withOpacity(0.6),
                    shadows: isFull
                        ? [
                            Shadow(
                                blurRadius: 3,
                                color: Colors.black.withOpacity(0.3),
                                offset: const Offset(1, 1))
                          ]
                        : [],
                  ),
                ),
              );
            }),

            // Merkezdeki + butonu
            GestureDetector(
              onTap: _showAddDialog,
              child: Container(
                height: size * 0.28,
                width: size * 0.28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Colors.grey.shade100, Colors.grey.shade300],
                  ),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 15,
                        offset: const Offset(5, 5)),
                    const BoxShadow(
                        color: Colors.white,
                        blurRadius: 10,
                        offset: Offset(-5, -5)),
                  ],
                ),
                child: Center(
                  child: Container(
                    height: size * 0.20,
                    width: size * 0.20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF2E406E), Color(0xFF1A2542)],
                      ),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.8), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.4),
                            blurRadius: 5,
                            spreadRadius: 1),
                      ],
                    ),
                    child: const Icon(Icons.add, color: Colors.white, size: 30),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── CUSTOM PAINTER ────────────────────────────────────────────────────────────

class SlicePainter extends CustomPainter {
  final int slotCount;
  final double sliceAngle;
  final String? pressedSlotKey;
  final Map<String, dynamic> medicines;

  SlicePainter({
    required this.slotCount,
    required this.sliceAngle,
    required this.pressedSlotKey,
    required this.medicines,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (int i = 0; i < slotCount; i++) {
      final isFull = medicines.containsKey('slot_${i + 1}');
      final isPressed = pressedSlotKey == "$i";
      final startAngle = (sliceAngle * i) - (pi / 2);

      final slicePaint = Paint()..style = PaintingStyle.fill;

      if (isFull) {
        slicePaint.shader = SweepGradient(
          startAngle: startAngle,
          endAngle: startAngle + sliceAngle,
          colors: isPressed
              ? [const Color(0xFFA5E67F), const Color(0xFF8BC34A)]
              : [const Color(0xFF7FB060), const Color(0xFF5A8F40)],
          tileMode: TileMode.repeated,
        ).createShader(rect);
      } else {
        slicePaint.shader = RadialGradient(
          center: Alignment.center,
          radius: 0.9,
          colors: isPressed
              ? [const Color(0xFFE3F2FD), const Color(0xFFBBDEFB)]
              : [const Color(0xFFFFFFFF), const Color(0xFFECEFF1)],
        ).createShader(rect);
      }

      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(rect, startAngle, sliceAngle, false)
        ..close();

      canvas.drawPath(path, slicePaint);

      if (isPressed) {
        canvas.drawPath(
          path,
          Paint()
            ..color = Colors.white.withOpacity(0.3)
            ..style = PaintingStyle.fill,
        );
      }

      canvas.drawPath(path, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant SlicePainter oldDelegate) => true;
}
