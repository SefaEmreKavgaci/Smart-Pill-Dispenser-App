import 'package:firebase_core/firebase_core.dart'; // YENİ EKLENDİ
import 'package:firebase_database/firebase_database.dart';
import 'dart:math';

class FirebaseService {
  // iOS'un Amerikan sunucusuna gitme inadını kırıp zorla Belçika adresimizi veriyoruz:
  final DatabaseReference _dbRef = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: 'https://kapsul-db9f7-default-rtdb.europe-west1.firebasedatabase.app',
  ).ref();

  // E-posta adresindeki geçersiz karakterleri temizlemek için yardımcı fonksiyon
  String _sanitizeEmail(String email) {
    return email.replaceAll('.', '_').replaceAll('@', '_');
  }

  // --- KULLANICI İŞLEMLERİ ---

  // Yeni kullanıcı ekleme (Kayıt Ol)
  Future<bool> registerUser({
    required String email,
    required String password,
    required String role,
    required String name,
    required String surname,
  }) async {
    String sanitizedEmail = _sanitizeEmail(email);
    
    // Kullanıcı zaten var mı kontrolü
    final snapshot = await _dbRef.child('users').child(sanitizedEmail).get();
    if (snapshot.exists) {
      return false; // Kullanıcı zaten var
    }

    String? patientId;
    if (role == 'patient') {
      patientId = await _generateUniquePatientId();
    }

    // Yeni kullanıcıyı oluştur
    await _dbRef.child('users').child(sanitizedEmail).set({
      'email': email, // Orijinal e-postayı da saklayalım
      'password': password,
      'role': role,
      'name': name,
      'surname': surname,
      'deviceCode': null,
      if (patientId != null) 'patientId': patientId,
    });
    return true; // Kayıt başarılı
  }

  // 6 Haneli Patient ID oluşturma
  Future<String> _generateUniquePatientId() async {
    final rand = Random();
    while (true) {
      // 100000 - 999999 aralığında rastgele 6 haneli sayı
      int generated = 100000 + rand.nextInt(900000);
      String patientId = generated.toString();
      
      // Çakışma var mı diye kontrol et
      final existing = await findPatientByPatientId(patientId);
      if (existing == null) {
        return patientId;
      }
    }
  }

  // Kullanıcı girişi kontrolü (Giriş Yap)
  Future<Map<String, dynamic>?> loginUser(String email, String password) async {
    String sanitizedEmail = _sanitizeEmail(email);
    
    final snapshot = await _dbRef.child('users').child(sanitizedEmail).get();
    
    if (snapshot.exists) {
      // Veriyi Map'e çeviriyoruz
      Map<dynamic, dynamic> data = snapshot.value as Map<dynamic, dynamic>;
      
      if (data['password'] == password) {
        // Şifre doğruysa kullanıcı verilerini döndür
        return Map<String, dynamic>.from(data);
      }
    }
    return null; // Kullanıcı yok veya şifre hatalı
  }

  // --- İLAÇ VE GEÇMİŞ İŞLEMLERİ (CANLI DİNLEME) ---

  // İlaçları canlı dinlemek için
  Stream<DatabaseEvent> listenToMedicines(String email) {
    String sanitizedEmail = _sanitizeEmail(email);
    return _dbRef.child('users').child(sanitizedEmail).child('medicines').onValue;
  }

  // Geçmişi canlı dinlemek için
  Stream<DatabaseEvent> listenToHistory(String email) {
    String sanitizedEmail = _sanitizeEmail(email);
    return _dbRef.child('users').child(sanitizedEmail).child('history').onValue;
  }

  // Geçmişe yeni bir kayıt atmak için
  Future<void> addHistoryRecord(String email, String uniqueId, Map<String, dynamic> historyData) async {
    String sanitizedEmail = _sanitizeEmail(email);
    await _dbRef.child('users').child(sanitizedEmail).child('history').child(uniqueId).set(historyData);
  }

  // İlaç içildiğinde (veya eklendiğinde/çıkarıldığında) veritabanından silmek/yönetmek için
  Future<void> deleteMedicine(String email, String medKey) async {
    String sanitizedEmail = _sanitizeEmail(email);
    await _dbRef.child('users').child(sanitizedEmail).child('medicines').child(medKey).remove();
  }

  // Kullanıcı profil bilgilerini (isim vb.) tek seferlik çekmek için
  Future<Map<String, dynamic>?> getUserProfile(String email) async {
    String sanitizedEmail = _sanitizeEmail(email);
    final snapshot = await _dbRef.child('users').child(sanitizedEmail).get();
    
    if (snapshot.exists) {
      return Map<String, dynamic>.from(snapshot.value as Map);
    }
    return null;
  }

  // ESP32'nin cihaz durumunu (Pil, Wi-Fi) canlı dinlemek için
  Stream<DatabaseEvent> listenToDeviceStatus(String email) {
    String sanitizedEmail = _sanitizeEmail(email);
    return _dbRef.child('users').child(sanitizedEmail).child('device_status').onValue;
  }

  // Cihaz simülasyonunu tetiklemek (Manuel test butonu için)
  Future<void> updateDeviceStatusSimulation(String email, int battery, bool isConnected) async {
    String sanitizedEmail = _sanitizeEmail(email);
    await _dbRef.child('users').child(sanitizedEmail).child('device_status').update({
      'battery': battery,
      'isConnected': isConnected,
      'lastUpdate': ServerValue.timestamp,
    });
  }

  // --- BAKICI (CAREGIVER) İŞLEMLERİ ---

  // Bakıcıya kayıtlı hastaların listesini canlı dinlemek için
  Stream<DatabaseEvent> listenToCaregiverPatients(String caregiverEmail) {
    String sanitizedEmail = _sanitizeEmail(caregiverEmail);
    // Bakıcının altındaki 'patients' düğümünü dinliyoruz
    return _dbRef.child('users').child(sanitizedEmail).child('patients').onValue;
  }

  // Cihaz koduna göre hastayı bulma (Query)
  Future<String?> findPatientByDeviceCode(String deviceCode) async {
    final snapshot = await _dbRef.child('users')
        .orderByChild('deviceCode')
        .equalTo(deviceCode)
        .once();

    if (snapshot.snapshot.exists) {
      Map data = snapshot.snapshot.value as Map;
      // İlk bulduğu kullanıcının key'ini (yani e-postasını) döndürür
      return data.keys.first.toString();
    }
    return null;
  }

  // 6 Haneli Patient ID'ye göre hastayı bulma (Query)
  Future<String?> findPatientByPatientId(String patientId) async {
    // Önce String olarak ara
    var snapshot = await _dbRef.child('users')
        .orderByChild('patientId')
        .equalTo(patientId)
        .once();

    if (snapshot.snapshot.exists) {
      Map data = snapshot.snapshot.value as Map;
      return data.keys.first.toString();
    }
    
    // Kullanıcı eğer manuel girerse integer (sayı) olarak kaydolmuş olabilir, int tipinde tekrar ara
    int? numericId = int.tryParse(patientId);
    if (numericId != null) {
      var snapshotNumeric = await _dbRef.child('users')
          .orderByChild('patientId')
          .equalTo(numericId)
          .once();
      
      if (snapshotNumeric.snapshot.exists) {
        Map data = snapshotNumeric.snapshot.value as Map;
        return data.keys.first.toString();
      }
    }

    return null;
  }

  // Bakıcının listesine hasta ekleme
  Future<bool> addPatientToCaregiver(String caregiverEmail, String patientEmail) async {
    String caregiverSanitized = _sanitizeEmail(caregiverEmail);
    String patientSanitized = _sanitizeEmail(patientEmail);
    
    // Zaten ekli mi kontrolü
    final snapshot = await _dbRef.child('users').child(caregiverSanitized).child('patients').child(patientSanitized).get();
    if (snapshot.exists) return false;

    // Listeye ekle
    await _dbRef.child('users').child(caregiverSanitized).child('patients').child(patientSanitized).set({
      'addedAt': ServerValue.timestamp,
    });
    return true;
  }

  // Bakıcının listesinden hasta silme
  Future<void> removePatientFromCaregiver(String caregiverEmail, String patientEmail) async {
    String caregiverSanitized = _sanitizeEmail(caregiverEmail);
    String patientSanitized = _sanitizeEmail(patientEmail);
    
    await _dbRef.child('users').child(caregiverSanitized).child('patients').child(patientSanitized).remove();
  }

  /// slot_fromSlot ve üzerindeki tüm slotları bir aşağı kaydırır.
  /// Kullanım: slot_1 silindikten sonra slot_2→slot_1, slot_3→slot_2, ...
  Future<void> shiftSlotsDown(String email, Map<String, dynamic> medicines, int fromSlot) async {
    final sanitized = _sanitizeEmail(email);

    final toShift = medicines.keys
        .where((k) => k.startsWith('slot_'))
        .map((k) => int.tryParse(k.split('_')[1]) ?? 0)
        .where((n) => n >= fromSlot)
        .toList()
      ..sort();

    for (final num in toShift) {
      final oldKey = 'slot_$num';
      final newKey = 'slot_${num - 1}';
      final data = Map<String, dynamic>.from(medicines[oldKey] as Map)
        ..['slotNumber'] = num - 1;
      await _dbRef.child('users').child(sanitized).child('medicines').child(newKey).set(data);
      await _dbRef.child('users').child(sanitized).child('medicines').child(oldKey).remove();
    }
  }

  // Kullanıcının Cihaz Kodunu ve Adresini Güncelleme veya Silme
  Future<void> updateDeviceCode(String email, String? newDeviceCode, {String? deviceUrl}) async {
    String sanitizedEmail = _sanitizeEmail(email);
    await _dbRef.child('users').child(sanitizedEmail).update({
      'deviceCode': newDeviceCode,
      'deviceUrl': deviceUrl,
    });
  }

  /// Kullanıcıya ait tüm ilaç kayıtlarını Firebase'den siler.
  Future<void> clearMedicines(String email) async {
    String sanitizedEmail = _sanitizeEmail(email);
    await _dbRef.child('users').child(sanitizedEmail).child('medicines').remove();
  }
}