/// Scan history provider — stores scan results in Hive for persistence.
/// Hive boxes map cleanly to DB tables for future migration.
library;
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/analysis_models.dart';

class ScanHistoryProvider extends ChangeNotifier {
  static const String _boxName = 'scan_history';
  static const String _scanEntriesKey = 'entries';
  static const String _callEntriesKey = 'call_entries';
  static const int _maxEntries = 50;

  List<ScanHistoryEntry> _entries = [];
  List<CallHistoryEntry> _callEntries = [];
  bool _loaded = false;
  Box? _box;
  StreamSubscription<BoxEvent>? _boxSubscription;

  List<ScanHistoryEntry> get entries => List.unmodifiable(_entries);
  List<CallHistoryEntry> get callEntries => List.unmodifiable(_callEntries);
  List<ScanHistoryEntry> get recentEntries => _entries.take(10).toList();
  List<CallHistoryGroup> get groupedCallHistory {
    final Map<String, List<CallHistoryEntry>> grouped = {};
    for (final entry in _callEntries) {
      grouped.putIfAbsent(entry.personKey, () => []).add(entry);
    }

    final groups = grouped.entries.map((item) {
      final calls = List<CallHistoryEntry>.from(item.value)
        ..sort((a, b) => b.endedAt.compareTo(a.endedAt));
      final latest = calls.first;
      return CallHistoryGroup(
        personKey: item.key,
        displayName: latest.displayName,
        phoneNumber: latest.phoneNumber,
        calls: calls,
      );
    }).toList()
      ..sort((a, b) => b.latestCall.endedAt.compareTo(a.latestCall.endedAt));

    return groups;
  }

  int get totalScans => _entries.length;
  int get threatsBlocked => _entries.where((e) => e.riskLevel == 'HIGH').length;
  int get verifiedSafe => _entries.where((e) => e.riskLevel == 'LOW').length;
  int get moderateThreats =>
      _entries.where((e) => e.riskLevel == 'MEDIUM').length;
  int get totalCallCount => _callEntries.length;
  int get callThreatsFound =>
      _callEntries.where((entry) => entry.riskLevel == 'HIGH').length;
  int get verifiedCallsSafe =>
      _callEntries.where((entry) => entry.riskLevel == 'LOW').length;

  /// Load history from Hive
  Future<void> loadHistory() async {
    if (_loaded) return;
    try {
      _box = await Hive.openBox(_boxName);
      _hydrateFromBox(_box!);
      _boxSubscription?.cancel();
      _boxSubscription = _box!.watch().listen((event) {
        if (event.key == _scanEntriesKey || event.key == _callEntriesKey) {
          _hydrateFromBox(_box!);
          notifyListeners();
        }
      });
      _loaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('ScanHistoryProvider: Failed to load: $e');
      _loaded = true;
    }
  }

  /// Add a new scan result
  Future<void> addScan(ScanHistoryEntry entry) async {
    _entries.insert(0, entry);
    if (_entries.length > _maxEntries) {
      _entries = _entries.sublist(0, _maxEntries);
    }
    notifyListeners();
    await _persist();
  }

  /// Add a completed call record
  Future<void> addCall(CallHistoryEntry entry) async {
    _callEntries.removeWhere((item) => item.id == entry.id);
    _callEntries.insert(0, entry);
    if (_callEntries.length > _maxEntries) {
      _callEntries = _callEntries.sublist(0, _maxEntries);
    }
    notifyListeners();
    await _persist();
  }

  /// Update an existing call record (e.g., edited display name or notes).
  Future<void> updateCallEntry(CallHistoryEntry updated) async {
    final index = _callEntries.indexWhere((item) => item.id == updated.id);
    if (index < 0) return;
    _callEntries[index] = updated;
    notifyListeners();
    await _persist();
  }

  /// Delete a single call record by ID.
  Future<void> deleteCallEntry(String id) async {
    _callEntries.removeWhere((item) => item.id == id);
    notifyListeners();
    await _persist();
  }

  /// Delete all call records for a given person key.
  Future<void> deleteCallGroup(String personKey) async {
    _callEntries.removeWhere((item) => item.personKey == personKey);
    notifyListeners();
    await _persist();
  }

  /// Persist to Hive
  Future<void> _persist() async {
    try {
      _box ??= await Hive.openBox(_boxName);
      await _box!.put(_scanEntriesKey, _entries.map((e) => e.toJson()).toList());
      await _box!.put(
        _callEntriesKey,
        _callEntries.map((entry) => entry.toJson()).toList(),
      );
    } catch (e) {
      debugPrint('ScanHistoryProvider: Failed to persist: $e');
    }
  }

  /// Clear all history
  Future<void> clearHistory() async {
    _entries.clear();
    _callEntries.clear();
    notifyListeners();
    try {
      _box ??= await Hive.openBox(_boxName);
      await _box!.clear();
    } catch (e) {
      debugPrint('ScanHistoryProvider: Failed to clear: $e');
    }
  }

  void _hydrateFromBox(Box box) {
    _entries = _decodeScans(box.get(_scanEntriesKey));
    _entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    _callEntries = _decodeCalls(box.get(_callEntriesKey));
    _callEntries.sort((a, b) => b.endedAt.compareTo(a.endedAt));
  }

  static Future<void> storeCallEntry(CallHistoryEntry entry) async {
    try {
      final box = await Hive.openBox(_boxName);
      final current = _decodeCalls(box.get(_callEntriesKey));
      current.removeWhere((item) => item.id == entry.id);
      current.insert(0, entry);
      if (current.length > _maxEntries) {
        current.removeRange(_maxEntries, current.length);
      }
      await box.put(
        _callEntriesKey,
        current.map((item) => item.toJson()).toList(),
      );
    } catch (e) {
      debugPrint('ScanHistoryProvider: Failed to store call entry: $e');
    }
  }

  static List<ScanHistoryEntry> _decodeScans(dynamic raw) {
    if (raw is! List) return [];
    return raw.map((entry) {
      if (entry is Map) {
        return ScanHistoryEntry.fromJson(Map<String, dynamic>.from(entry));
      }
      return ScanHistoryEntry.fromJson(
        Map<String, dynamic>.from(jsonDecode(entry.toString())),
      );
    }).toList();
  }

  static List<CallHistoryEntry> _decodeCalls(dynamic raw) {
    if (raw is! List) return [];
    return raw.map((entry) {
      if (entry is Map) {
        return CallHistoryEntry.fromJson(Map<String, dynamic>.from(entry));
      }
      return CallHistoryEntry.fromJson(
        Map<String, dynamic>.from(jsonDecode(entry.toString())),
      );
    }).toList();
  }

  @override
  void dispose() {
    _boxSubscription?.cancel();
    super.dispose();
  }
}
