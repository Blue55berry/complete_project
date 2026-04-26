/// Call Log Provider — stores call-monitoring events recorded by the
/// floating bubble overlay, rendered in the Call Monitoring tab as a
/// native-style call history.
library;

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

enum CallDirection { incoming, outgoing, missed }
enum CallVerdict { safe, aiDetected, suspicious, unknown }

class CallLogEntry {
  final String id;
  final DateTime timestamp;
  final String phoneNumber;
  final String contactName;
  final CallDirection direction;
  final int durationSeconds; // 0 if missed / not tracked
  final CallVerdict verdict;
  final double riskScore; // 0.0 – 1.0
  final String explanation;

  const CallLogEntry({
    required this.id,
    required this.timestamp,
    required this.phoneNumber,
    required this.contactName,
    required this.direction,
    required this.durationSeconds,
    required this.verdict,
    required this.riskScore,
    required this.explanation,
  });

  /// Label shown in the list (contact name or formatted number)
  String get displayName =>
      contactName.isNotEmpty ? contactName : _formatNumber(phoneNumber);

  String _formatNumber(String raw) {
    if (raw.isEmpty) return 'Unknown Number';
    // Keep it readable as-is; real apps would format with libphonenumber
    return raw;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'phoneNumber': phoneNumber,
    'contactName': contactName,
    'direction': direction.name,
    'durationSeconds': durationSeconds,
    'verdict': verdict.name,
    'riskScore': riskScore,
    'explanation': explanation,
  };

  factory CallLogEntry.fromJson(Map<String, dynamic> j) => CallLogEntry(
    id: j['id'] ?? '',
    timestamp: DateTime.tryParse(j['timestamp'] ?? '') ?? DateTime.now(),
    phoneNumber: j['phoneNumber'] ?? '',
    contactName: j['contactName'] ?? '',
    direction: CallDirection.values.firstWhere(
      (d) => d.name == j['direction'],
      orElse: () => CallDirection.incoming,
    ),
    durationSeconds: (j['durationSeconds'] as num?)?.toInt() ?? 0,
    verdict: CallVerdict.values.firstWhere(
      (v) => v.name == j['verdict'],
      orElse: () => CallVerdict.unknown,
    ),
    riskScore: (j['riskScore'] as num?)?.toDouble() ?? 0.0,
    explanation: j['explanation'] ?? '',
  );
}

class CallLogProvider extends ChangeNotifier {
  static const String _boxName = 'call_log';
  static const int _maxEntries = 100;

  List<CallLogEntry> _entries = [];
  bool _loaded = false;

  List<CallLogEntry> get entries => List.unmodifiable(_entries);

  int get totalCalls => _entries.length;
  int get aiDetectedCalls =>
      _entries.where((e) => e.verdict == CallVerdict.aiDetected || e.verdict == CallVerdict.suspicious).length;
  int get safeCalls => _entries.where((e) => e.verdict == CallVerdict.safe).length;

  Future<void> loadLog() async {
    if (_loaded) return;
    try {
      final box = await Hive.openBox(_boxName);
      final raw = box.get('entries');
      if (raw != null) {
        final list = (raw as List).map((e) {
          if (e is Map) {
            return CallLogEntry.fromJson(Map<String, dynamic>.from(e));
          }
          return CallLogEntry.fromJson(
            Map<String, dynamic>.from(jsonDecode(e.toString())),
          );
        }).toList();
        _entries = list.cast<CallLogEntry>();
        _entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      }
      _loaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('CallLogProvider: Failed to load: $e');
      _loaded = true;
    }
  }

  /// Add a call log entry (called when a monitored call session ends)
  Future<void> addCallEntry(CallLogEntry entry) async {
    _entries.insert(0, entry);
    if (_entries.length > _maxEntries) {
      _entries = _entries.sublist(0, _maxEntries);
    }
    notifyListeners();
    await _persist();
  }

  /// Clear all call log
  Future<void> clearLog() async {
    _entries.clear();
    notifyListeners();
    try {
      final box = await Hive.openBox(_boxName);
      await box.clear();
    } catch (e) {
      debugPrint('CallLogProvider: Failed to clear: $e');
    }
  }

  Future<void> _persist() async {
    try {
      final box = await Hive.openBox(_boxName);
      await box.put('entries', _entries.map((e) => e.toJson()).toList());
    } catch (e) {
      debugPrint('CallLogProvider: Failed to persist: $e');
    }
  }
}
