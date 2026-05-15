import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../models/linky_models.dart';
import 'hourly_history_cache.dart';

class ApiLinkyRepository implements LinkyRepository {
  const ApiLinkyRepository({
    this.baseUrl = const String.fromEnvironment(
      'LINKY_API_BASE_URL',
      defaultValue: defaultBaseUrl,
    ),
    this.timeout = const Duration(seconds: 8),
    this.subscribedPowerKva = 15,
    this.energyPrices = TempoEnergyPrices.esStrasbourg20250801,
    this.hourlyHistoryCache,
  });

  static const defaultBaseUrl = 'http://raspberrypi.local:8080';

  final String baseUrl;
  final Duration timeout;
  final int subscribedPowerKva;
  final TempoEnergyPrices energyPrices;
  final HourlyHistoryCache? hourlyHistoryCache;

  @override
  Future<LinkySnapshot> fetchCurrentSnapshot() async {
    final current =
        await _getData('/api/linky/current') as Map<String, dynamic>;
    final history = await _getTodayHourlyHistoryOrEmpty();
    final rows = history.whereType<Map<String, dynamic>>().toList();
    return _snapshotFromRows(
      current: current,
      rows: rows,
      timestampFallback: DateTime.now(),
      tempoTomorrow: _tomorrowTempoColor(current),
    );
  }

  static TempoDayColor _tomorrowTempoColor(Map<String, dynamic> current) {
    final fromLinky = _tempoColor(current['demain']);
    if (fromLinky != TempoDayColor.unknown) {
      return fromLinky;
    }

    final fromProviderProfile = _tempoColor(current['pjourf_next']);
    if (fromProviderProfile != TempoDayColor.unknown) {
      return fromProviderProfile;
    }

    return TempoDayColor.unknown;
  }

  @override
  Future<LinkySnapshot> fetchCachedCurrentSnapshot() async {
    final rows = hourlyHistoryCache?.read(DateTime.now())?.rows ?? const [];
    if (rows.isEmpty) {
      throw const LinkyApiException('Aucune donnée du jour en cache');
    }
    return _snapshotFromRows(
      current: rows.last,
      rows: rows,
      timestampFallback: DateTime.now(),
      tempoTomorrow: TempoDayColor.unknown,
    );
  }

  @override
  Future<LinkySnapshot> fetchDailySnapshot(DateTime date) async {
    final rows = await _getHourlyRowsForDate(date, forceRefresh: true);
    if (rows.isEmpty) {
      throw const LinkyApiException('Aucune donnée pour cette journée');
    }
    return _snapshotFromRows(
      current: rows.last,
      rows: rows,
      timestampFallback: date,
      tempoTomorrow: TempoDayColor.unknown,
    );
  }

  @override
  Future<LinkySnapshot> fetchCachedDailySnapshot(DateTime date) async {
    final rows = hourlyHistoryCache?.read(date)?.rows ?? const [];
    if (rows.isEmpty) {
      throw const LinkyApiException(
        'Aucune donnée en cache pour cette journée',
      );
    }
    return _snapshotFromRows(
      current: rows.last,
      rows: rows,
      timestampFallback: date,
      tempoTomorrow: TempoDayColor.unknown,
    );
  }

  @override
  Future<InstantConsumptionSnapshot> fetchInstantConsumption() async {
    final data =
        await _getData('/api/linky/realtime?duration=30m&resolution=raw')
            as List<dynamic>;
    final rows = data.whereType<Map<String, dynamic>>().toList();
    final points = [
      for (final row in rows)
        if (_parseTimestamp(row['timestamp']) != null)
          PhaseInstantPoint(
            timestamp: _parseTimestamp(row['timestamp'])!,
            phase1Va: readInt(row, 'sinsts1_va'),
            phase2Va: readInt(row, 'sinsts2_va'),
            phase3Va: readInt(row, 'sinsts3_va'),
          ),
    ];

    return InstantConsumptionSnapshot(
      updatedAt: DateTime.now(),
      points: points,
    );
  }

  LinkySnapshot _snapshotFromRows({
    required Map<String, dynamic> current,
    required List<Map<String, dynamic>> rows,
    required DateTime timestampFallback,
    required TempoDayColor tempoTomorrow,
  }) {
    final timestamp =
        _parseTimestamp(current['timestamp']) ?? timestampFallback;
    final currentIndexWh = _totalEnergyIndex(current);
    final firstIndexWh = rows.isEmpty
        ? currentIndexWh
        : _totalEnergyIndex(rows.first);
    final dailyConsumptionWh = math.max(0, currentIndexWh - firstIndexWh);
    final firstRow = rows.isEmpty ? current : rows.first;

    return LinkySnapshot(
      timestamp: timestamp,
      powerVa: _currentPowerVa(current),
      dailyConsumptionWh: dailyConsumptionWh,
      dailyEnergyCostEuro: energyPrices.estimateCostEuro(current, firstRow),
      peakConsumptionWh: math.max(
        0,
        _peakEnergyIndex(current) - _peakEnergyIndex(firstRow),
      ),
      offPeakConsumptionWh: math.max(
        0,
        _offPeakEnergyIndex(current) - _offPeakEnergyIndex(firstRow),
      ),
      monthlyConsumptionKwh: currentIndexWh / 1000,
      subscribedPowerKva: subscribedPowerKva,
      currentTariffLabel: current['tariff_label']?.toString() ?? 'Inconnu',
      tempoToday: _tempoColor(current['tariff_label']),
      tempoTomorrow: tempoTomorrow,
      hourlyConsumption: _hourlyConsumption(rows),
      missingPastHours: _missingPastHours(rows),
    );
  }

  String _formatApiDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  Future<List<dynamic>> _getTodayHourlyHistoryOrEmpty() async {
    try {
      return await _getHourlyRowsForDate(DateTime.now(), forceRefresh: true);
    } catch (_) {
      return const [];
    }
  }

  Future<List<Map<String, dynamic>>> _getHourlyRowsForDate(
    DateTime date, {
    required bool forceRefresh,
  }) async {
    final cache = hourlyHistoryCache;
    final isToday = _isSameDay(date, DateTime.now());

    if (cache != null && !forceRefresh) {
      final cached = cache.read(date);
      if (cached != null && !cached.isEmpty) {
        return cached.rows;
      }
    }

    final path =
        '/api/linky/history?date=${_formatApiDate(date)}&resolution=hour';
    final history = await _getData(path) as List<dynamic>;
    final rows = history.whereType<Map<String, dynamic>>().toList();

    if (cache == null) {
      return rows;
    }

    if (isToday) {
      return cache.mergeToday(date, rows);
    }

    await cache.write(date, rows);
    return rows;
  }

  static bool _isSameDay(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  Future<void> checkHealth() async {
    final uri = Uri.parse('$baseUrl/api/health');
    try {
      final response = await http.get(uri).timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw LinkyApiException(
          'API joignable, mais /api/health retourne HTTP ${response.statusCode}',
        );
      }
    } catch (error) {
      if (error is LinkyApiException) {
        rethrow;
      }
      throw LinkyApiException(
        'Impossible de joindre $baseUrl/api/health. '
        'Teste cette adresse dans le navigateur du téléphone.',
      );
    }
  }

  Future<Object?> _getData(String path) async {
    final uri = Uri.parse('$baseUrl$path');
    late http.Response response;
    try {
      response = await http.get(uri).timeout(timeout);
    } catch (error) {
      throw LinkyApiException('Connexion impossible à $baseUrl$path');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = response.body.trim();
      throw LinkyApiException(
        body.isEmpty
            ? 'HTTP ${response.statusCode} sur $path'
            : 'HTTP ${response.statusCode} sur $path : $body',
      );
    }

    late Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw LinkyApiException('Réponse JSON invalide sur $path');
    }

    if (decoded is! Map<String, dynamic> || !decoded.containsKey('data')) {
      throw const LinkyApiException('Réponse API inattendue');
    }

    final data = decoded['data'];
    if (data == null) {
      throw const LinkyApiException('Aucune donnée Linky disponible');
    }
    return data;
  }

  static int _currentPowerVa(Map<String, dynamic> row) {
    final phasePower =
        readInt(row, 'sinsts1_va') +
        readInt(row, 'sinsts2_va') +
        readInt(row, 'sinsts3_va');

    return phasePower > 0 ? phasePower : readInt(row, 'sinsts_va');
  }

  static int _totalEnergyIndex(Map<String, dynamic> row) {
    var total = 0;
    for (var index = 1; index <= 6; index++) {
      total += readInt(row, 'easf${index.toString().padLeft(2, '0')}_wh');
    }
    return total;
  }

  static int _peakEnergyIndex(Map<String, dynamic> row) {
    return readInt(row, 'easf02_wh') +
        readInt(row, 'easf04_wh') +
        readInt(row, 'easf06_wh');
  }

  static int _offPeakEnergyIndex(Map<String, dynamic> row) {
    return readInt(row, 'easf01_wh') +
        readInt(row, 'easf03_wh') +
        readInt(row, 'easf05_wh');
  }

  static List<HourlyConsumption> _hourlyConsumption(
    List<Map<String, dynamic>> rows,
  ) {
    if (rows.length < 2) {
      final now = DateTime.now();
      return [
        for (var hour = 0; hour < 24; hour++)
          HourlyConsumption(
            hour: DateTime(now.year, now.month, now.day, hour),
            consumptionWh: 0,
            tempoColor: TempoDayColor.unknown,
          ),
      ];
    }

    final buckets = <DateTime, int>{};
    final bucketColors = <DateTime, TempoDayColor>{};
    for (var index = 1; index < rows.length; index++) {
      final previous = rows[index - 1];
      final current = rows[index];
      final timestamp = _parseTimestamp(current['timestamp']);
      if (timestamp == null) {
        continue;
      }

      final delta = _totalEnergyIndex(current) - _totalEnergyIndex(previous);
      if (delta < 0) {
        continue;
      }

      final hour = DateTime(
        timestamp.year,
        timestamp.month,
        timestamp.day,
        timestamp.hour,
      );
      buckets[hour] = (buckets[hour] ?? 0) + delta;
      bucketColors[hour] = _tempoColor(current['tariff_label']);
    }

    final firstTimestamp =
        _parseTimestamp(rows.first['timestamp']) ?? DateTime.now();
    final start = DateTime(
      firstTimestamp.year,
      firstTimestamp.month,
      firstTimestamp.day,
    );
    return [
      for (var hour = 0; hour < 24; hour++)
        HourlyConsumption(
          hour: start.add(Duration(hours: hour)),
          consumptionWh: buckets[start.add(Duration(hours: hour))] ?? 0,
          tempoColor:
              bucketColors[start.add(Duration(hours: hour))] ??
              TempoDayColor.unknown,
        ),
    ];
  }

  static List<DateTime> _missingPastHours(List<Map<String, dynamic>> rows) {
    final now = DateTime.now();
    final currentHour = DateTime(now.year, now.month, now.day, now.hour);
    final knownHours = <DateTime>{};

    for (final row in rows) {
      final timestamp = _parseTimestamp(row['timestamp']);
      if (timestamp == null || !_isSameDay(timestamp, now)) {
        continue;
      }
      knownHours.add(
        DateTime(
          timestamp.year,
          timestamp.month,
          timestamp.day,
          timestamp.hour,
        ),
      );
    }

    if (knownHours.isEmpty) {
      return const [];
    }

    final sortedHours = knownHours.toList()..sort();
    final missing = <DateTime>[];
    for (
      var hour = sortedHours.first;
      hour.isBefore(currentHour);
      hour = hour.add(const Duration(hours: 1))
    ) {
      if (!knownHours.contains(hour)) {
        missing.add(hour);
      }
    }
    return missing;
  }

  static TempoDayColor _tempoColor(Object? label) {
    final value = label?.toString().toUpperCase() ?? '';
    if (value.contains('BLEU') || value.contains('BLUE')) {
      return TempoDayColor.blue;
    }
    if (value.contains('BLANC') || value.contains('WHITE')) {
      return TempoDayColor.white;
    }
    if (value.contains('ROUGE') || value.contains('RED')) {
      return TempoDayColor.red;
    }
    if (value.contains('HCJB') || value.contains('HPJB')) {
      return TempoDayColor.blue;
    }
    if (value.contains('HCJW') || value.contains('HPJW')) {
      return TempoDayColor.white;
    }
    if (value.contains('HCJR') || value.contains('HPJR')) {
      return TempoDayColor.red;
    }
    return TempoDayColor.unknown;
  }

  static DateTime? _parseTimestamp(Object? value) {
    if (value == null) {
      return null;
    }
    return DateTime.tryParse(value.toString());
  }

  static int readInt(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class LinkyApiException implements Exception {
  const LinkyApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
