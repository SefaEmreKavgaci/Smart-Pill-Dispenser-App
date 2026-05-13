import 'package:flutter/material.dart';
import '../services/firebase_service.dart';
import '../services/esp_service.dart';
import 'login_screen.dart';

class PatientSettingsScreen extends StatefulWidget {
  final String userEmail;
  const PatientSettingsScreen({super.key, required this.userEmail});

  @override
  State<PatientSettingsScreen> createState() => _PatientSettingsScreenState();
}

class _PatientSettingsScreenState extends State<PatientSettingsScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  final EspService _espService = EspService();

  String? currentDeviceCode;
  String? currentDeviceUrl;
  String? fullName;
  String? patientId;
  bool isLoading = true;
  bool isPairing = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final userData = await _firebaseService.getUserProfile(widget.userEmail);
    if (userData != null && mounted) {
      final url = userData['deviceUrl'] as String?;
      // Kayıtlı adres varsa EspService'e yükle
      if (url != null && url.isNotEmpty) {
        EspService.setBaseUrl(url);
      }
      setState(() {
        currentDeviceCode = userData['deviceCode'];
        currentDeviceUrl = url;
        fullName = "${userData['name']} ${userData['surname']}";
        patientId = userData['patientId']?.toString();
        isLoading = false;
      });
    } else if (mounted) {
      setState(() => isLoading = false);
    }
  }

  /// Eşleştirme:
  /// 1. Girilen adrese bağlanmayı dene
  /// 2. Başarılıysa Firebase'deki ilaçları sil
  /// 3. ESP32'ye boş program gönder (sıfırla)
  /// 4. Cihaz kodu + adresini Firebase'e kaydet
  Future<void> _pairDevice() async {
    final name = 'Kapsül';
    final address = 'kapsul.local';

    setState(() => isPairing = true);

    // URL'yi EspService'e set et ve bağlantıyı test et
    EspService.setBaseUrl(address);
    final schedule = await _espService.getSchedule();

    if (!mounted) return;

    if (schedule == null) {
      EspService.setBaseUrl(currentDeviceUrl ?? 'kapsul.local'); // geri al
      setState(() => isPairing = false);
      final hint = "\"kapsul.local\" could not be reached. Make sure the device is on and connected to the same Wi-Fi network.";
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(hint),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 8),
      ));
      return;
    }

    // Bağlantı başarılı → Firebase'deki eski ilaçları temizle
    await _firebaseService.clearMedicines(widget.userEmail);

    // ESP32'ye boş program gönder (sıfırla)
    await _espService.syncSchedule({});

    // Cihaz kodu + adresini Firebase'e kaydet
    await _firebaseService.updateDeviceCode(
      widget.userEmail,
      name,
      deviceUrl: address,
    );

    setState(() {
      currentDeviceCode = name;
      currentDeviceUrl = address;
      isPairing = false;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text("Device successfully paired! Compartments reset."),
      backgroundColor: Colors.green,
    ));
  }

  /// Bağlantıyı kes:
  /// 1. Firebase'deki ilaçları temizle
  /// 2. ESP32'ye boş program gönder (mümkünse)
  /// 3. Cihaz kodu + adresini sil
  void _removeDeviceCode() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Disconnect"),
        content: const Text(
          "Device connection will be severed and all medication data in compartments will be deleted. Are you sure?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);

              // Firebase'deki ilaçları temizle
              await _firebaseService.clearMedicines(widget.userEmail);

              // ESP32'ye boş program gönder (erişilebiliyorsa)
              await _espService.syncSchedule({});

              // Firebase'den cihaz bilgilerini sil
              await _firebaseService.updateDeviceCode(
                  widget.userEmail, null, deviceUrl: null);

              EspService.setBaseUrl('kapsul.local'); // varsayılana dön

              if (!mounted) return;
              setState(() {
                currentDeviceCode = null;
                currentDeviceUrl = null;
              });

              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text("Disconnected and medication data cleared."),
                backgroundColor: Colors.red,
              ));
            },
            child: const Text("Disconnect", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryColor = Color(0xFF2E406E);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
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
            child: const Center(
              child: Text(
                "Settings",
                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
          ),

          // --- İÇERİK ---
          Expanded(
            child: isLoading 
              ? const Center(child: CircularProgressIndicator(color: primaryColor))
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    // Profil Kartı
                    Container(
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                      child: ListTile(
                        leading: CircleAvatar(backgroundColor: primaryColor.withOpacity(0.1), child: const Icon(Icons.person, color: primaryColor)),
                        title: Text(fullName ?? "User", style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(widget.userEmail),
                            const SizedBox(height: 4),
                            Text("Patient ID: ${patientId ?? 'None'}", style: const TextStyle(color: primaryColor, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    // Cihaz Ayarları
                    const Padding(padding: EdgeInsets.only(left: 10, bottom: 10), child: Text("DEVICE CONNECTION", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12))),
                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                      child: currentDeviceCode == null
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Make sure you are connected to the same Wi-Fi network as the Capsule device and press Pair.",
                                style: TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: isPairing
                                  ? const Center(child: SizedBox(
                                      width: 36,
                                      height: 36,
                                      child: CircularProgressIndicator(strokeWidth: 3),
                                    ))
                                  : ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: primaryColor,
                                        foregroundColor: Colors.white,
                                      ),
                                      onPressed: _pairDevice,
                                      child: const Text("Pair"),
                                    ),
                              ),
                            ],
                          )
                        : ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.router, color: Colors.green),
                            title: Text(
                              currentDeviceCode!,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text("Connected • ${currentDeviceUrl ?? 'kapsul.local'}"),
                            trailing: IconButton(
                              icon: const Icon(Icons.link_off, color: Colors.red),
                              onPressed: _removeDeviceCode,
                              tooltip: "Disconnect",
                            ),
                          ),
                    ),

                    const SizedBox(height: 20),
                    
                    // Diğer Ayarlar
                    const Padding(padding: EdgeInsets.only(left: 10, bottom: 10), child: Text("APPLICATION", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12))),
                    Container(
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.logout, color: Colors.red),
                            title: const Text("Log Out", style: TextStyle(color: Colors.red)),
                            onTap: () {
                              Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const LoginScreen()), (route) => false);
                            },
                          ),
                        ],
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