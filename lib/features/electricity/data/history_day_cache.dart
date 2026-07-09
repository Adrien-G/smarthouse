import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class HistoryDayCache {
  const HistoryDayCache(this.preferences);

  final SharedPreferences preferences;

  static Future<HistoryDayCache> load() async {
    return HistoryDayCache(await SharedPreferences.getInstance());
  }

  List<Map<String, dynamic>>? read(DateTime date) {
    final raw = preferences.getString(_key(date));
    if (raw == null) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return null;
      }
      return decoded.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> write(DateTime date, List<Map<String, dynamic>> rows) async {
    await preferences.setString(_key(date), jsonEncode(rows));
  }

  String _key(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return 'history_day_cache_v1_$year-$month-$day';
  }
}
