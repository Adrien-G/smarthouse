import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class DetectedDevice {
  const DetectedDevice({
    required this.id,
    required this.name,
    required this.note,
    required this.savedAt,
    required this.totalW,
    required this.phase1W,
    required this.phase2W,
    required this.phase3W,
    required this.mainPhaseLabel,
  });

  final String id;
  final String name;
  final String note;
  final DateTime savedAt;
  final int totalW;
  final int phase1W;
  final int phase2W;
  final int phase3W;
  final String mainPhaseLabel;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'note': note,
      'saved_at': savedAt.toIso8601String(),
      'total_w': totalW,
      'phase1_w': phase1W,
      'phase2_w': phase2W,
      'phase3_w': phase3W,
      'main_phase_label': mainPhaseLabel,
    };
  }

  DetectedDevice copyWith({
    String? name,
    String? note,
    int? totalW,
    int? phase1W,
    int? phase2W,
    int? phase3W,
    String? mainPhaseLabel,
  }) {
    return DetectedDevice(
      id: id,
      name: name ?? this.name,
      note: note ?? this.note,
      savedAt: savedAt,
      totalW: totalW ?? this.totalW,
      phase1W: phase1W ?? this.phase1W,
      phase2W: phase2W ?? this.phase2W,
      phase3W: phase3W ?? this.phase3W,
      mainPhaseLabel: mainPhaseLabel ?? this.mainPhaseLabel,
    );
  }

  static DetectedDevice? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }

    final savedAt = DateTime.tryParse(value['saved_at']?.toString() ?? '');
    final name = value['name']?.toString().trim();
    if (savedAt == null || name == null || name.isEmpty) {
      return null;
    }

    return DetectedDevice(
      id: value['id']?.toString() ?? savedAt.microsecondsSinceEpoch.toString(),
      name: name,
      note: value['note']?.toString() ?? '',
      savedAt: savedAt,
      totalW: _readInt(value['total_w']),
      phase1W: _readInt(value['phase1_w']),
      phase2W: _readInt(value['phase2_w']),
      phase3W: _readInt(value['phase3_w']),
      mainPhaseLabel: value['main_phase_label']?.toString() ?? '',
    );
  }

  static int _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class DetectedDeviceStore {
  static const _key = 'detected_devices';

  static Future<List<DetectedDevice>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_key);
    if (encoded == null) {
      return const [];
    }

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) {
        return const [];
      }
      return [
        for (final item in decoded)
          if (DetectedDevice.fromJson(item) != null)
            DetectedDevice.fromJson(item)!,
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> save(List<DetectedDevice> devices) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _key,
      jsonEncode([for (final device in devices) device.toJson()]),
    );
  }
}
