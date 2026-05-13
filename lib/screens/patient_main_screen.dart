import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../services/firebase_service.dart';
import '../services/esp_service.dart';

// Ekranlar
import 'patient_dashboard_screen.dart';
import 'compartments_screen.dart';
import 'patient_history_screen.dart';
import 'patient_settings_screen.dart';

class PatientMainScreen extends StatefulWidget {
  final String currentUserEmail;
  const PatientMainScreen({super.key, required this.currentUserEmail});

  @override
  State<PatientMainScreen> createState() => _PatientMainScreenState();
}

class _PatientMainScreenState extends State<PatientMainScreen> {
  int _currentIndex = 0;
  Timer? _timer;
  Timer? _dialogTimer;        // Dialog içi 60 saniyelik auto-dismiss zamanlayıcısı
  bool _isDialogOpen = false;
  VoidCallback? _dismissDialog; // Dışarıdan dialog'u kapatan callback

  final FirebaseService _firebaseService = FirebaseService();
  final EspService _espService = EspService();

  Map<String, dynamic> _medicines = {};
  Map<String, dynamic> _history = {};

  StreamSubscription<DatabaseEvent>? _medSubscription;
  StreamSubscription<DatabaseEvent>? _historySubscription;

  // ESP32'den gelen güncelleme işlenirken tekrar işlemeyi engeller
  bool _isProcessingEspUpdate = false;

  @override
  void initState() {
    super.initState();
    _loadDeviceConfig();
    _startListeningToFirebase();

    // Her 10 saniyede: hem yerel saat kontrolü hem ESP32 durum sorgusu
    _timer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _checkMedicineTimes();
      _checkEspStatus();
    });
  }

  /// Kullanıcının kayıtlı cihaz adresini Firebase'den yükler ve EspService'e uygular.
  Future<void> _loadDeviceConfig() async {
    final firebaseService = FirebaseService();
    final userData = await firebaseService.getUserProfile(widget.currentUserEmail);
    if (userData != null) {
      final url = userData['deviceUrl'] as String?;
      if (url != null && url.isNotEmpty) {
        EspService.setBaseUrl(url);
      }
    }
  }

  void _startListeningToFirebase() {
    // İlaçları canlı dinle
    _medSubscription = _firebaseService.listenToMedicines(widget.currentUserEmail).listen((event) {
      if (event.snapshot.value != null) {
        setState(() {
          _medicines = Map<String, dynamic>.from(event.snapshot.value as Map);
        });
      } else {
        setState(() { _medicines = {}; });
      }
    });

    // Geçmişi canlı dinle (Zaten işlenmiş ilaçları tekrar sormamak için)
    _historySubscription = _firebaseService.listenToHistory(widget.currentUserEmail).listen((event) {
      if (event.snapshot.value != null) {
        _history = Map<String, dynamic>.from(event.snapshot.value as Map);
      } else {
        _history = {};
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _dialogTimer?.cancel();
    _medSubscription?.cancel();
    _historySubscription?.cancel();
    super.dispose();
  }

  /// Zaman tabanlı kontrol — yalnızca cihaz offline olduğunda fallback olarak çalışır.
  /// Dialog tetiklemez; dialog sadece _checkEspStatus tarafından (missed durumunda) açılır.
  void _checkMedicineTimes() {
    // Dialog açıksa timer bu fonksiyonu çalıştırmasın; dialog kendi zamanlayıcısını yönetiyor
    if (_isDialogOpen) return;

    final med = _medicines['slot_1'];
    if (med == null) return;

    final now = DateTime.now();
    final dateStr = med['date'] as String?;
    final timeStr = med['time'] as String;

    late final DateTime medTime;
    if (dateStr != null) {
      final d = DateTime.parse(dateStr);
      final parts = timeStr.split(':');
      medTime = DateTime(d.year, d.month, d.day,
          int.parse(parts[0]), int.parse(parts[1]));
    } else {
      final parts = timeStr.split(':');
      medTime = DateTime(now.year, now.month, now.day,
          int.parse(parts[0]), int.parse(parts[1]));
    }

    final diffInSeconds = now.difference(medTime).inSeconds;
    if (diffInSeconds < 0) return; // henüz zamanı gelmedi

    final alreadyProcessed = _history.values.any((h) =>
        h['slot'] == 1 && h['time'] == timeStr && h['date'] == dateStr);
    if (alreadyProcessed) return;

    // DEMO: 60 saniyelik pencere (prod: 3600 sn).
    // Cihaz online olsaydı _checkEspStatus zaten işlerdi.
    // Bu sadece cihaz offline iken devreye giren son güvence.
    if (diffInSeconds > 60) {
      final uniqueKey = 'slot_1_offline_${now.millisecondsSinceEpoch}';
      _firebaseService.addHistoryRecord(widget.currentUserEmail, uniqueKey, {
        'uniqueId': uniqueKey,
        'name': med['name'],
        'time': timeStr,
        'date': dateStr,
        'takenDate': now.toString(),
        'status': 'Missed',
        'slot': 1,
      });
      _firebaseService.deleteMedicine(widget.currentUserEmail, 'slot_1').then((_) async {
        await _firebaseService.shiftSlotsDown(widget.currentUserEmail, _medicines, 2);
        _espService.syncSchedule(_buildShiftedMap(_medicines));
      });
    }
  }

  /// ESP32'yi periyodik olarak sorgular.
  /// taken  → diyalogu kapat + Firebase'e sessizce "Alındı" yaz
  /// missed → ilaç alma diyalogu aç (kullanıcı 1 dk içinde "Aldım" diyebilir)
  /// pending → hiçbir şey yapma
  Future<void> _checkEspStatus() async {
    if (_isProcessingEspUpdate) return;

    final rawMed = _medicines['slot_1'];
    if (rawMed == null) return;

    final schedule = await _espService.getSchedule();
    if (schedule == null) return; // cihaz offline

    final slot1 = schedule.where((s) => s.slot == 1).firstOrNull;
    if (slot1 == null) return;
    if (slot1.status == 'pending') return; // henüz bir şey olmamış

    final med = Map<String, dynamic>.from(rawMed as Map);
    final timeStr = med['time'] as String?;
    final dateStr = med['date'] as String?;

    // Bu slot için zaten geçmiş kaydı var mı?
    final alreadyDone = _history.values.any((h) =>
        h['slot'] == 1 && h['time'] == timeStr && h['date'] == dateStr);
    if (alreadyDone) return;

    if (slot1.status == 'taken') {
      // ─── Cihazda alındı → dialogu kapat, sessizce işle ───────────────────
      _dismissDialog?.call(); // varsa açık dialogu kapat
      _isProcessingEspUpdate = true;

      final uniqueId = 'slot_1_esp_taken_${DateTime.now().millisecondsSinceEpoch}';
      await _firebaseService.addHistoryRecord(widget.currentUserEmail, uniqueId, {
        'uniqueId': uniqueId,
        'name': med['name'],
        'time': timeStr,
        'date': dateStr,
        'takenDate': DateTime.now().toString(),
        'status': 'Alındı',
        'slot': 1,
      });
      await _firebaseService.deleteMedicine(widget.currentUserEmail, 'slot_1');
      await _firebaseService.shiftSlotsDown(widget.currentUserEmail, _medicines, 2);
      await _espService.syncSchedule(_buildShiftedMap(_medicines));

      _isProcessingEspUpdate = false;

    } else if (slot1.status == 'missed') {
      // ─── Cihaz kaçırıldı işareti verdi → dialog aç (zaten açık değilse) ──
      if (!_isDialogOpen && mounted) {
        final uniqueId = 'slot_1_esp_missed_${DateTime.now().millisecondsSinceEpoch}';
        _showReminderDialog('slot_1', med, uniqueId);
      }
    }
  }

  /// slot_1 silindikten sonra ESP32'ye gönderilecek haritayı hesaplar.
  Map<String, dynamic> _buildShiftedMap(Map<String, dynamic> current) {
    final result = <String, dynamic>{};
    for (final entry in current.entries) {
      if (!entry.key.startsWith('slot_')) continue;
      final num = int.tryParse(entry.key.split('_')[1]) ?? 0;
      if (num <= 1) continue;
      final data = Map<String, dynamic>.from(entry.value as Map)
        ..['slotNumber'] = num - 1;
      result['slot_${num - 1}'] = data;
    }
    return result;
  }

  void _showReminderDialog(String key, Map<dynamic, dynamic> med, String uniqueId) {
    if (_isDialogOpen) return; // zaten açıksa tekrar açma
    setState(() => _isDialogOpen = true);

    // Dialog kapatma callback'ini dialog context ile kur
    // (context dışarıda yakalanacak, aşağıda _dismissDialog'a atanacak)
    BuildContext? dialogCtx;

    // DEMO: 60 saniye sonra dialog kapanır ve "Missed" olarak işaretlenir
    // (prod'da 3600 sn = 1 saat)
    _dialogTimer = Timer(const Duration(seconds: 60), () {
      _dismissDialog?.call();
      // Kullanıcı cevap vermedi → Kaçırıldı
      final now = DateTime.now();
      final autoKey = 'slot_1_auto_missed_${now.millisecondsSinceEpoch}';
      _firebaseService.addHistoryRecord(widget.currentUserEmail, autoKey, {
        'uniqueId': autoKey,
        'name': med['name'],
        'time': med['time'],
        'date': med['date'],
        'takenDate': now.toString(),
        'status': 'Missed',
        'slot': 1,
      });
      _firebaseService.deleteMedicine(widget.currentUserEmail, 'slot_1').then((_) async {
        await _firebaseService.shiftSlotsDown(widget.currentUserEmail, _medicines, 2);
        _espService.syncSchedule(_buildShiftedMap(_medicines));
      });
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dCtx) {
        dialogCtx = dCtx;
        _dismissDialog = () {
          if (dialogCtx != null && Navigator.of(dialogCtx!).canPop()) {
            Navigator.of(dialogCtx!).pop();
          }
        };
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.alarm, color: Color(0xFF2E406E)),
              SizedBox(width: 10),
              Text("Medication Time!"),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("${med['name']}", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF2E406E))),
              const SizedBox(height: 10),
              Text("It is time to take your medication for ${med['time']}."),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                _dialogTimer?.cancel();
                _dismissDialog?.call();
                final now = DateTime.now();
                await _firebaseService.addHistoryRecord(widget.currentUserEmail, uniqueId, {
                  'uniqueId': uniqueId,
                  'name': med['name'],
                  'time': med['time'],
                  'date': med['date'],
                  'takenDate': now.toString(),
                  'status': 'Skipped',
                  'slot': 1,
                });
                await _firebaseService.deleteMedicine(widget.currentUserEmail, 'slot_1');
                await _firebaseService.shiftSlotsDown(widget.currentUserEmail, _medicines, 2);
                _espService.syncSchedule(_buildShiftedMap(_medicines));
              },
              child: const Text("Snooze / Skip", style: TextStyle(color: Colors.red)),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.check),
              label: const Text("Yes, I took it"),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              onPressed: () async {
                _dialogTimer?.cancel();
                _dismissDialog?.call();
                final now = DateTime.now();
                await _firebaseService.addHistoryRecord(widget.currentUserEmail, uniqueId, {
                  'uniqueId': uniqueId,
                  'name': med['name'],
                  'time': med['time'],
                  'date': med['date'],
                  'takenDate': now.toString(),
                  'status': 'Taken',
                  'slot': 1,
                });
                await _firebaseService.deleteMedicine(widget.currentUserEmail, 'slot_1');
                await _firebaseService.shiftSlotsDown(widget.currentUserEmail, _medicines, 2);
                _espService.syncSchedule(_buildShiftedMap(_medicines));
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Great! Stay healthy."), backgroundColor: Colors.green));
              },
            ),
          ],
        );
      },
    ).whenComplete(() {
      // Dialog her kapandığında (buton, timer veya dismiss) state'i temizle
      _dialogTimer?.cancel();
      _dialogTimer = null;
      _dismissDialog = null;
      if (mounted) setState(() => _isDialogOpen = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      DashboardScreen(currentUserEmail: widget.currentUserEmail), 
      // const kelimesini kaldırdık çünkü artık içine dinamik bir e-posta alıyor:
      CompartmentsScreen(currentUserEmail: widget.currentUserEmail),            
      PatientHistoryScreen(currentUserEmail: widget.currentUserEmail),          
      PatientSettingsScreen(userEmail: widget.currentUserEmail), 
    ];

    final Color primaryColor = const Color(0xFF2E406E);

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
        selectedItemColor: primaryColor,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.pie_chart), label: 'Capsule'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}