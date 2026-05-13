import 'dart:convert';
import 'package:http/http.dart' as http;

/// ESP32'nin "gece yarısından dakika" formatını "HH:MM" stringe çevirir.
String minutesToTimeString(int minutes) {
  final h = (minutes ~/ 60).toString().padLeft(2, '0');
  final m = (minutes % 60).toString().padLeft(2, '0');
  return '$h:$m';
}

/// "HH:MM" stringini gece yarısından dakika formatına çevirir.
int timeStringToMinutes(String time) {
  final parts = time.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

class EspSlotStatus {
  final int month;     // ay (1-12)
  final int day;       // gün (1-31)
  final int time;      // gece yarısından dakika
  final int slot;      // ESP32 slot numarası (1-based, app ile aynı)
  final String status; // "pending", "taken", "missed"

  EspSlotStatus({
    required this.month,
    required this.day,
    required this.time,
    required this.slot,
    required this.status,
  });

  factory EspSlotStatus.fromJson(Map<String, dynamic> json) {
    return EspSlotStatus(
      month: (json['month'] as int?) ?? DateTime.now().month,
      day:   (json['day']   as int?) ?? DateTime.now().day,
      time:   json['time']   as int,
      slot:   json['slot']   as int,
      status: json['status'] as String,
    );
  }
}

class EspService {
  /// Uygulama genelinde kullanılan cihaz adresi.
  /// Ayarlar ekranından veya Firebase'den yüklenince güncellenir.
  static String _baseUrl = 'http://kapsul.local';
  static const Duration _timeout = Duration(seconds: 10);

  /// Adres "192.168.1.5" veya "kapsul.local" formatında girilebilir.
  /// http:// prefix'i yoksa otomatik eklenir.
  static void setBaseUrl(String hostOrIp) {
    final clean = hostOrIp.trim();
    _baseUrl = clean.startsWith('http') ? clean : 'http://$clean';
  }

  static String get currentBaseUrl => _baseUrl;

  /// GET /api/schedule
  /// ESP32'deki aktif programı ve her dozun durumunu getirir.
  Future<List<EspSlotStatus>?> getSchedule() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/schedule'))
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = jsonDecode(response.body);
        return jsonList
            .map((e) => EspSlotStatus.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
      // ignore: avoid_print
      print('[EspService] getSchedule HTTP ${response.statusCode}: ${response.body}');
    } catch (e) {
      // ignore: avoid_print
      print('[EspService] getSchedule error → $_baseUrl/api/schedule | $e');
    }
    return null;
  }

  /// POST /api/schedule
  /// Firebase'deki ilaç listesini ESP32'ye senkronize eder.
  /// [medicines] parametresi Firebase'deki ilaç haritasıdır.
  /// Anahtar formatı: slot_1, slot_2, ..., slot_14
  /// ESP32 slot numarası = uygulama slot numarası (doğrudan eşleme).
  Future<bool> syncSchedule(Map<String, dynamic> medicines) async {
    final List<Map<String, dynamic>> payload = [];

    medicines.forEach((key, value) {
      // Anahtar formatı: slot_N
      if (!key.toString().startsWith('slot_')) return;
      final slotNumber = int.tryParse(key.split('_')[1]);
      final timeStr = value['time'] as String?;
      final dateStr = value['date'] as String?; // "YYYY-MM-DD"

      if (slotNumber == null || timeStr == null) return;

      int? month;
      int? day;
      if (dateStr != null) {
        final parts = dateStr.split('-');
        if (parts.length == 3) {
          month = int.tryParse(parts[1]);
          day = int.tryParse(parts[2]);
        }
      }

      payload.add({
        'slot': slotNumber,
        'time': timeStringToMinutes(timeStr),
        if (month != null) 'month': month,
        if (day != null) 'day': day,
      });
    });

    // Slotları sıraya göre gönder
    payload.sort((a, b) => (a['slot'] as int).compareTo(b['slot'] as int));

    return _postSchedule(payload);
  }

  Future<bool> _postSchedule(List<Map<String, dynamic>> payload) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/schedule'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(_timeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// POST /api/dispense
  /// Belirtilen slot numarasını hemen açar (manuel override).
  /// [slotNumber] 1-based uygulama slot numarasıdır (ESP32 ile aynı).
  Future<bool> dispense({required int slotNumber}) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/dispense'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'slot': slotNumber}),
          )
          .timeout(_timeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
