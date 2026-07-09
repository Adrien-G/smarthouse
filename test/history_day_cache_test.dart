import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smarthouse/features/electricity/data/history_day_cache.dart';

void main() {
  test('stores and reads a completed history day', () async {
    SharedPreferences.setMockInitialValues({});
    final cache = await HistoryDayCache.load();
    final date = DateTime(2026, 7, 8);

    await cache.write(date, [
      {
        'timestamp': '2026-07-08T00:00:00',
        'tariff_label': 'BLEU HC',
        'easf01_wh': 1000,
      },
    ]);

    final rows = cache.read(date);

    expect(rows, isNotNull);
    expect(rows, hasLength(1));
    expect(rows!.first['tariff_label'], 'BLEU HC');
    expect(cache.read(DateTime(2026, 7, 7)), isNull);
  });
}
