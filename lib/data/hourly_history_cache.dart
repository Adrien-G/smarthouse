import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/linky_models.dart';

class HourlyHistoryCache {
  const HourlyHistoryCache(this.preferences);

  final SharedPreferences preferences;

  static Future<HourlyHistoryCache> load() async {
    return HourlyHistoryCache(await SharedPreferences.getInstance());
  }

  CachedHourlyHistory? read(DateTime date) {
    final encoded = preferences.getString(_key(date));
    if (encoded == null) {
      return null;
    }

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) {
        return null;
      }
      return CachedHourlyHistory(
        rows: decoded.whereType<Map>().map((row) {
          return row.map((key, value) => MapEntry(key.toString(), value));
        }).toList(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> write(DateTime date, List<Map<String, dynamic>> rows) async {
    await preferences.setString(_key(date), jsonEncode(rows));
  }

  Future<void> clearAll() async {
    final keys = preferences.getKeys().where(
      (key) => key.startsWith('history_hour_'),
    );
    for (final key in keys) {
      await preferences.remove(key);
    }
  }

  Future<List<Map<String, dynamic>>> mergeToday(
    DateTime date,
    List<Map<String, dynamic>> freshRows,
  ) async {
    final cachedRows = read(date)?.rows ?? const [];
    final now = DateTime.now();
    final currentHour = DateTime(now.year, now.month, now.day, now.hour);
    final merged = <String, Map<String, dynamic>>{};

    for (final row in cachedRows) {
      final timestamp = DateTime.tryParse(row['timestamp']?.toString() ?? '');
      if (timestamp == null) {
        continue;
      }
      final hour = DateTime(
        timestamp.year,
        timestamp.month,
        timestamp.day,
        timestamp.hour,
      );
      if (hour.isBefore(currentHour)) {
        merged[hour.toIso8601String()] = row;
      }
    }

    for (final row in freshRows) {
      final timestamp = DateTime.tryParse(row['timestamp']?.toString() ?? '');
      if (timestamp == null) {
        continue;
      }
      final hour = DateTime(
        timestamp.year,
        timestamp.month,
        timestamp.day,
        timestamp.hour,
      );
      merged[hour.toIso8601String()] = row;
    }

    final rows = merged.keys.toList()..sort();
    final result = [for (final key in rows) merged[key]!];
    await write(date, result);
    return result;
  }

  String _key(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return 'history_hour_$year-$month-$day';
  }
}
