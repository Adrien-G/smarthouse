import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettings.load();
  final hourlyHistoryCache = await HourlyHistoryCache.load();
  runApp(
    SmartHouseApp(settings: settings, hourlyHistoryCache: hourlyHistoryCache),
  );
}

class AppSettings {
  const AppSettings({required this.apiBaseUrl});

  static const apiBaseUrlKey = 'linky_api_base_url';

  final String apiBaseUrl;

  static Future<AppSettings> load() async {
    final preferences = await SharedPreferences.getInstance();
    return AppSettings(
      apiBaseUrl:
          preferences.getString(apiBaseUrlKey) ??
          ApiLinkyRepository.defaultBaseUrl,
    );
  }

  Future<void> save() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(apiBaseUrlKey, apiBaseUrl);
  }
}

class SmartHouseApp extends StatelessWidget {
  const SmartHouseApp({
    super.key,
    this.repository,
    this.hourlyHistoryCache,
    this.settings = const AppSettings(
      apiBaseUrl: ApiLinkyRepository.defaultBaseUrl,
    ),
  });

  final LinkyRepository? repository;
  final HourlyHistoryCache? hourlyHistoryCache;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xff1f7a5c);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SmartHouse Linky',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xfff6f7f3),
      ),
      home: SmartHouseHome(
        initialApiBaseUrl: settings.apiBaseUrl,
        repository: repository,
        hourlyHistoryCache: hourlyHistoryCache,
      ),
    );
  }
}

enum TempoDayColor { blue, white, red, unknown }

extension TempoDayColorLabel on TempoDayColor {
  String get label {
    return switch (this) {
      TempoDayColor.blue => 'Bleu',
      TempoDayColor.white => 'Blanc',
      TempoDayColor.red => 'Rouge',
      TempoDayColor.unknown => 'Inconnu',
    };
  }

  Color get accent {
    return switch (this) {
      TempoDayColor.blue => const Color(0xff3279bd),
      TempoDayColor.white => const Color(0xff7b8794),
      TempoDayColor.red => const Color(0xffc23b35),
      TempoDayColor.unknown => const Color(0xff6b7280),
    };
  }
}

class LinkySnapshot {
  const LinkySnapshot({
    required this.timestamp,
    required this.powerVa,
    required this.dailyConsumptionWh,
    required this.dailyEnergyCostEuro,
    required this.peakConsumptionWh,
    required this.offPeakConsumptionWh,
    required this.monthlyConsumptionKwh,
    required this.subscribedPowerKva,
    required this.currentTariffLabel,
    required this.tempoToday,
    required this.tempoTomorrow,
    required this.hourlyConsumption,
    required this.missingPastHours,
  });

  final DateTime timestamp;
  final int powerVa;
  final int dailyConsumptionWh;
  final double dailyEnergyCostEuro;
  final int peakConsumptionWh;
  final int offPeakConsumptionWh;
  final double monthlyConsumptionKwh;
  final int subscribedPowerKva;
  final String currentTariffLabel;
  final TempoDayColor tempoToday;
  final TempoDayColor tempoTomorrow;
  final List<HourlyConsumption> hourlyConsumption;
  final List<DateTime> missingPastHours;

  double get currentPowerKw => powerVa / 1000;
  double get dailyConsumptionKwh => dailyConsumptionWh / 1000;
  double get peakConsumptionKwh => peakConsumptionWh / 1000;
  double get offPeakConsumptionKwh => offPeakConsumptionWh / 1000;
  double get loadRatio => powerVa / (subscribedPowerKva * 1000);
}

class TempoEnergyPrices {
  const TempoEnergyPrices({
    required this.bluePeak,
    required this.blueOffPeak,
    required this.whitePeak,
    required this.whiteOffPeak,
    required this.redPeak,
    required this.redOffPeak,
  });

  // Tarifs reglementes ES Energies Strasbourg TTC, applicables au 01/08/2025.
  // Les index Tempo Linky sont stockes par couleur dans l'ordre HC puis HP :
  // EASF01 bleu HC, EASF02 bleu HP, EASF03 blanc HC, etc.
  static const esStrasbourg20250801 = TempoEnergyPrices(
    bluePeak: 0.14938,
    blueOffPeak: 0.12322,
    whitePeak: 0.17302,
    whiteOffPeak: 0.13906,
    redPeak: 0.64678,
    redOffPeak: 0.14602,
  );

  final double bluePeak;
  final double blueOffPeak;
  final double whitePeak;
  final double whiteOffPeak;
  final double redPeak;
  final double redOffPeak;

  double estimateCostEuro(
    Map<String, dynamic> current,
    Map<String, dynamic> first,
  ) {
    return _periodCost(current, first, 'easf01_wh', blueOffPeak) +
        _periodCost(current, first, 'easf02_wh', bluePeak) +
        _periodCost(current, first, 'easf03_wh', whiteOffPeak) +
        _periodCost(current, first, 'easf04_wh', whitePeak) +
        _periodCost(current, first, 'easf05_wh', redOffPeak) +
        _periodCost(current, first, 'easf06_wh', redPeak);
  }

  double _periodCost(
    Map<String, dynamic> current,
    Map<String, dynamic> first,
    String key,
    double pricePerKwh,
  ) {
    final deltaWh = math.max(
      0,
      ApiLinkyRepository.readInt(current, key) -
          ApiLinkyRepository.readInt(first, key),
    );
    return deltaWh / 1000 * pricePerKwh;
  }
}

class HourlyConsumption {
  const HourlyConsumption({
    required this.hour,
    required this.consumptionWh,
    required this.tempoColor,
  });

  final DateTime hour;
  final int consumptionWh;
  final TempoDayColor tempoColor;

  double get consumptionKwh => consumptionWh / 1000;
}

abstract class LinkyRepository {
  Future<LinkySnapshot> fetchCurrentSnapshot();
  Future<LinkySnapshot> fetchCachedCurrentSnapshot();
  Future<LinkySnapshot> fetchDailySnapshot(DateTime date);
  Future<LinkySnapshot> fetchCachedDailySnapshot(DateTime date);
  Future<InstantConsumptionSnapshot> fetchInstantConsumption();
}

class PhaseInstantPoint {
  const PhaseInstantPoint({
    required this.timestamp,
    required this.phase1Va,
    required this.phase2Va,
    required this.phase3Va,
  });

  final DateTime timestamp;
  final int phase1Va;
  final int phase2Va;
  final int phase3Va;

  int get totalVa => phase1Va + phase2Va + phase3Va;
}

class CachedHourlyHistory {
  const CachedHourlyHistory({required this.rows});

  final List<Map<String, dynamic>> rows;

  bool get isEmpty => rows.isEmpty;
  bool get isCompleteDay => rows.length >= 24;
}

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

class InstantConsumptionSnapshot {
  const InstantConsumptionSnapshot({
    required this.updatedAt,
    required this.points,
  });

  final DateTime updatedAt;
  final List<PhaseInstantPoint> points;

  PhaseInstantPoint? get latest => points.isEmpty ? null : points.last;
}

final _showLegacyMetrics = DateTime.now().year == 0;

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

class LinkyLoadState {
  const LinkyLoadState.connecting() : message = 'Connexion au Raspberry...';

  const LinkyLoadState.loadingPeriod(String period)
    : message = 'Récupération $period...';

  final String message;
}

class MockLinkyRepository implements LinkyRepository {
  const MockLinkyRepository();

  @override
  Future<LinkySnapshot> fetchCurrentSnapshot() async {
    await Future<void>.delayed(const Duration(milliseconds: 350));

    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final values = <int>[
      120,
      95,
      88,
      82,
      90,
      140,
      260,
      410,
      520,
      360,
      300,
      280,
      330,
      290,
      270,
      310,
      460,
      720,
      860,
      690,
      540,
      410,
      260,
      170,
    ];

    return LinkySnapshot(
      timestamp: now,
      powerVa: 1840,
      dailyConsumptionWh: values.take(now.hour + 1).fold(0, (a, b) => a + b),
      dailyEnergyCostEuro: 0.68,
      peakConsumptionWh: 3350,
      offPeakConsumptionWh: 1280,
      monthlyConsumptionKwh: 312.4,
      subscribedPowerKva: 15,
      currentTariffLabel: 'HP BLEU',
      tempoToday: TempoDayColor.blue,
      tempoTomorrow: TempoDayColor.white,
      missingPastHours: const [],
      hourlyConsumption: [
        for (var index = 0; index < values.length; index++)
          HourlyConsumption(
            hour: start.add(Duration(hours: index)),
            consumptionWh: values[index],
            tempoColor: index < 6 ? TempoDayColor.red : TempoDayColor.blue,
          ),
      ],
    );
  }

  @override
  Future<LinkySnapshot> fetchDailySnapshot(DateTime date) async {
    return fetchCurrentSnapshot();
  }

  @override
  Future<LinkySnapshot> fetchCachedCurrentSnapshot() async {
    return fetchCurrentSnapshot();
  }

  @override
  Future<LinkySnapshot> fetchCachedDailySnapshot(DateTime date) async {
    return fetchDailySnapshot(date);
  }

  @override
  Future<InstantConsumptionSnapshot> fetchInstantConsumption() async {
    final now = DateTime.now();
    return InstantConsumptionSnapshot(
      updatedAt: now,
      points: [
        for (var index = 29; index >= 0; index--)
          PhaseInstantPoint(
            timestamp: now.subtract(Duration(minutes: index)),
            phase1Va: 420 + (index % 5) * 35,
            phase2Va: 610 + (index % 7) * 28,
            phase3Va: 380 + (index % 3) * 44,
          ),
      ],
    );
  }
}

class SmartHouseHome extends StatefulWidget {
  const SmartHouseHome({
    super.key,
    required this.initialApiBaseUrl,
    this.repository,
    this.hourlyHistoryCache,
  });

  final String initialApiBaseUrl;
  final LinkyRepository? repository;
  final HourlyHistoryCache? hourlyHistoryCache;

  @override
  State<SmartHouseHome> createState() => _SmartHouseHomeState();
}

class _SmartHouseHomeState extends State<SmartHouseHome> {
  var _selectedIndex = 0;
  late String _apiBaseUrl;
  late LinkyRepository _repository;

  @override
  void initState() {
    super.initState();
    _apiBaseUrl = widget.initialApiBaseUrl;
    _repository =
        widget.repository ??
        ApiLinkyRepository(
          baseUrl: _apiBaseUrl,
          hourlyHistoryCache: widget.hourlyHistoryCache,
        );
  }

  Future<void> _changeApiBaseUrl(String value) async {
    final normalized = _normalizeApiBaseUrlValue(value);
    await AppSettings(apiBaseUrl: normalized).save();

    setState(() {
      _apiBaseUrl = normalized;
      _repository =
          widget.repository ??
          ApiLinkyRepository(
            baseUrl: normalized,
            hourlyHistoryCache: widget.hourlyHistoryCache,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final page = switch (_selectedIndex) {
      0 => EnergyDashboardPage(
        key: ValueKey('today-page-$_apiBaseUrl'),
        apiBaseUrl: _apiBaseUrl,
        repository: _repository,
        onChangeApiBaseUrl: _changeApiBaseUrl,
      ),
      1 => InstantConsumptionPage(
        key: ValueKey('instant-page-$_apiBaseUrl'),
        repository: _repository,
      ),
      _ => HistoryPage(
        key: ValueKey('history-page-$_apiBaseUrl'),
        apiBaseUrl: _apiBaseUrl,
        repository: _repository,
      ),
    };

    return Scaffold(
      body: page,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: "Aujourd'hui",
          ),
          NavigationDestination(
            icon: Icon(Icons.show_chart),
            selectedIcon: Icon(Icons.show_chart),
            label: 'Instantané',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'Historique',
          ),
        ],
      ),
    );
  }
}

class EnergyDashboardPage extends StatefulWidget {
  const EnergyDashboardPage({
    super.key,
    required this.apiBaseUrl,
    required this.repository,
    required this.onChangeApiBaseUrl,
  });

  final String apiBaseUrl;
  final LinkyRepository repository;
  final ValueChanged<String> onChangeApiBaseUrl;

  @override
  State<EnergyDashboardPage> createState() => _EnergyDashboardPageState();
}

class _EnergyDashboardPageState extends State<EnergyDashboardPage> {
  LinkySnapshot? _snapshot;
  Object? _error;
  LinkyLoadState _loadState = const LinkyLoadState.connecting();
  var _loadingInitial = true;
  var _refreshing = false;

  @override
  void initState() {
    super.initState();
    _loadTodayOnStartup();
  }

  Future<void> _loadTodayOnStartup() async {
    _updateLoadState(const LinkyLoadState.loadingPeriod('du cache local'));
    try {
      final snapshot = await widget.repository.fetchCachedCurrentSnapshot();
      if (!mounted) {
        return;
      }
      setState(() {
        _snapshot = snapshot;
        _error = null;
        _loadingInitial = false;
      });
      await _refresh(showInitialLoading: false);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
      });
      await _refresh(showInitialLoading: true);
    }
  }

  Future<void> _refresh({bool showInitialLoading = false}) async {
    if (!mounted || _refreshing) {
      return;
    }

    if (showInitialLoading || _snapshot == null) {
      setState(() {
        _loadingInitial = true;
        _error = null;
      });
    } else {
      setState(() {
        _refreshing = true;
      });
    }

    _updateLoadState(const LinkyLoadState.connecting());
    try {
      if (widget.repository is ApiLinkyRepository) {
        await (widget.repository as ApiLinkyRepository).checkHealth();
      }

      _updateLoadState(
        const LinkyLoadState.loadingPeriod('des données du jour'),
      );
      final snapshot = await widget.repository.fetchCurrentSnapshot();
      if (!mounted) {
        return;
      }
      setState(() {
        _snapshot = snapshot;
        _error = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingInitial = false;
          _refreshing = false;
        });
      }
    }
  }

  void _updateLoadState(LinkyLoadState state) {
    if (!mounted) {
      _loadState = state;
      return;
    }
    setState(() {
      _loadState = state;
    });
  }

  Future<void> _changeApiBaseUrl(String value) async {
    widget.onChangeApiBaseUrl(value);
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;

    return Scaffold(
      body: SafeArea(
        child: Builder(
          builder: (context) {
            if (_loadingInitial && snapshot == null) {
              return _LoadingView(message: _loadState.message);
            }

            if (snapshot == null) {
              return _ErrorView(
                apiBaseUrl: widget.apiBaseUrl,
                error: _error,
                onRetry: () => _refresh(showInitialLoading: true),
                onChangeApiBaseUrl: _changeApiBaseUrl,
              );
            }

            return _DashboardContent(
              snapshot: snapshot,
              apiBaseUrl: widget.apiBaseUrl,
              onRefresh: () => _refresh(showInitialLoading: false),
              onChangeApiBaseUrl: _changeApiBaseUrl,
              isRefreshing: _refreshing,
              refreshError: _error,
            );
          },
        ),
      ),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({
    required this.snapshot,
    required this.apiBaseUrl,
    required this.onRefresh,
    required this.onChangeApiBaseUrl,
    required this.isRefreshing,
    required this.refreshError,
  });

  final LinkySnapshot snapshot;
  final String apiBaseUrl;
  final Future<void> Function() onRefresh;
  final ValueChanged<String> onChangeApiBaseUrl;
  final bool isRefreshing;
  final Object? refreshError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 720;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 16 : 28,
          vertical: 20,
        ),
        children: [
          _Header(
            snapshot: snapshot,
            apiBaseUrl: apiBaseUrl,
            onRefresh: onRefresh,
            onChangeApiBaseUrl: onChangeApiBaseUrl,
            isRefreshing: isRefreshing,
          ),
          const SizedBox(height: 18),
          if (refreshError != null) ...[
            _InlineStatusMessage(
              icon: Icons.cloud_off,
              message:
                  'Dernière actualisation impossible, affichage du cache conservé.',
            ),
            const SizedBox(height: 12),
          ],
          _TodaySummaryHero(snapshot: snapshot),
          const SizedBox(height: 14),
          _PeakOffPeakCard(snapshot: snapshot),
          const SizedBox(height: 14),
          _TomorrowTempoCard(snapshot: snapshot),
          const SizedBox(height: 18),
          if (_showLegacyMetrics)
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _MetricTile(
                  icon: Icons.bolt,
                  label: 'Puissance instantanée',
                  value: '${snapshot.currentPowerKw.toStringAsFixed(2)} kW',
                  detail: '${snapshot.powerVa} VA',
                  color: const Color(0xffd97706),
                ),
                _MetricTile(
                  icon: Icons.today,
                  label: 'Aujourd’hui',
                  value:
                      '${snapshot.dailyConsumptionKwh.toStringAsFixed(2)} kWh',
                  detail: snapshot.tempoToday.label,
                  color: snapshot.tempoToday.accent,
                ),
                _MetricTile(
                  icon: Icons.calendar_month,
                  label: 'Mois en cours',
                  value:
                      '${snapshot.monthlyConsumptionKwh.toStringAsFixed(1)} kWh',
                  detail: 'Index local',
                  color: const Color(0xff4f46e5),
                ),
                _MetricTile(
                  icon: Icons.speed,
                  label: 'Abonnement',
                  value: '${snapshot.subscribedPowerKva} kVA',
                  detail: '${(snapshot.loadRatio * 100).round()} % utilisé',
                  color: const Color(0xff0f766e),
                ),
              ],
            ),
          const SizedBox(height: 22),
          if (_showLegacyMetrics)
            _SectionHeader(
              title: 'Consommation horaire',
              subtitle: 'Données locales reçues depuis le compteur',
              trailing: Text('24 h', style: theme.textTheme.labelLarge),
            ),
          if (_showLegacyMetrics) const SizedBox(height: 12),
          if (snapshot.missingPastHours.isNotEmpty) ...[
            _InlineStatusMessage(
              icon: Icons.manage_search,
              message: _missingHoursMessage(snapshot.missingPastHours),
            ),
            const SizedBox(height: 12),
          ],
          SizedBox(
            height: compact ? 220 : 280,
            child: _HourlyChart(values: snapshot.hourlyConsumption),
          ),
        ],
      ),
    );
  }

  String _missingHoursMessage(List<DateTime> hours) {
    final preview = hours.take(4).map((hour) => '${hour.hour}h').join(', ');
    final suffix = hours.length > 4 ? '...' : '';
    final plural = hours.length > 1 ? 's' : '';
    return '${hours.length} heure$plural passée$plural sans donnée dans l’historique : $preview$suffix';
  }
}

class InstantConsumptionPage extends StatefulWidget {
  const InstantConsumptionPage({super.key, required this.repository});

  final LinkyRepository repository;

  @override
  State<InstantConsumptionPage> createState() => _InstantConsumptionPageState();
}

class _InstantConsumptionPageState extends State<InstantConsumptionPage> {
  InstantConsumptionSnapshot? _snapshot;
  Object? _error;
  var _loadingInitial = true;
  var _refreshing = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh(showInitialLoading: true);
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool showInitialLoading = false}) async {
    if (!mounted || _refreshing) {
      return;
    }

    if (showInitialLoading || _snapshot == null) {
      setState(() {
        _loadingInitial = true;
        _error = null;
      });
    } else {
      setState(() {
        _refreshing = true;
      });
    }

    try {
      final snapshot = await widget.repository.fetchInstantConsumption();
      if (!mounted) {
        return;
      }
      setState(() {
        _snapshot = snapshot;
        _error = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingInitial = false;
          _refreshing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 720;
    final snapshot = _snapshot;

    return SafeArea(
      child: ListView(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 16 : 28,
          vertical: 20,
        ),
        children: [
          _InstantHeader(
            onRefresh: () => _refresh(showInitialLoading: snapshot == null),
            isRefreshing: _refreshing,
          ),
          const SizedBox(height: 18),
          if (_loadingInitial && snapshot == null)
            const SizedBox(
              height: 220,
              child: _LoadingView(
                message: 'Récupération des 30 dernières minutes...',
              ),
            )
          else if (snapshot == null)
            _EmptyHistoryMessage(
              icon: Icons.cloud_off,
              title: 'Données instantanées indisponibles',
              message:
                  _error?.toString() ??
                  'Impossible de charger les dernières mesures.',
              action: FilledButton.icon(
                onPressed: () => _refresh(showInitialLoading: true),
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
            )
          else ...[
            if (_error != null) ...[
              _InlineStatusMessage(
                icon: Icons.cloud_off,
                message:
                    'Dernière actualisation impossible, affichage conservé.',
              ),
              const SizedBox(height: 12),
            ],
            _InstantContent(snapshot: snapshot),
          ],
        ],
      ),
    );
  }
}

class _InstantHeader extends StatelessWidget {
  const _InstantHeader({required this.onRefresh, required this.isRefreshing});

  final VoidCallback onRefresh;
  final bool isRefreshing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Instantané',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '30 dernières minutes - actualisation 10 s',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isRefreshing) ...[
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
              const SizedBox(width: 10),
            ],
            IconButton.filledTonal(
              onPressed: isRefreshing ? null : onRefresh,
              tooltip: 'Actualiser',
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ],
    );
  }
}

class _InlineStatusMessage extends StatelessWidget {
  const _InlineStatusMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xfffffbeb),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xfffde68a)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: const Color(0xff92400e)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xff78350f),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InstantContent extends StatelessWidget {
  const _InstantContent({required this.snapshot});

  final InstantConsumptionSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final latest = snapshot.latest;

    if (latest == null) {
      return const _EmptyHistoryMessage(
        icon: Icons.show_chart,
        title: 'Pas encore de données',
        message: 'Aucune mesure disponible sur les 30 dernières minutes.',
      );
    }

    return Column(
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _PhaseStat(
              label: 'Phase 1',
              averageVa: _averageVa(snapshot.points, (point) => point.phase1Va),
              trend: _phaseTrend(snapshot.points, (point) => point.phase1Va),
            ),
            _PhaseStat(
              label: 'Phase 2',
              averageVa: _averageVa(snapshot.points, (point) => point.phase2Va),
              trend: _phaseTrend(snapshot.points, (point) => point.phase2Va),
            ),
            _PhaseStat(
              label: 'Phase 3',
              averageVa: _averageVa(snapshot.points, (point) => point.phase3Va),
              trend: _phaseTrend(snapshot.points, (point) => point.phase3Va),
            ),
            _PhaseStat(
              label: 'Total',
              averageVa: _averageVa(snapshot.points, (point) => point.totalVa),
              trend: _phaseTrend(snapshot.points, (point) => point.totalVa),
            ),
          ],
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 280,
          child: _InstantPhasesChart(points: snapshot.points),
        ),
        const SizedBox(height: 10),
        Text('Dernière mesure à ${_formatTime(latest.timestamp)}'),
      ],
    );
  }

  int _averageVa(
    List<PhaseInstantPoint> points,
    int Function(PhaseInstantPoint point) readValue,
  ) {
    if (points.isEmpty) {
      return 0;
    }
    final total = points.fold<int>(0, (sum, point) => sum + readValue(point));
    return (total / points.length).round();
  }

  _PhaseTrend _phaseTrend(
    List<PhaseInstantPoint> points,
    int Function(PhaseInstantPoint point) readValue,
  ) {
    if (points.length < 4) {
      return _PhaseTrend.stable;
    }

    final midpoint = points.length ~/ 2;
    final startAverage = _averageVa(points.take(midpoint).toList(), readValue);
    final endAverage = _averageVa(points.skip(midpoint).toList(), readValue);
    final delta = endAverage - startAverage;
    final threshold = math.max(80, startAverage * 0.08);

    if (delta > threshold) {
      return _PhaseTrend.up;
    }
    if (delta < -threshold) {
      return _PhaseTrend.down;
    }
    return _PhaseTrend.stable;
  }
}

enum _PhaseTrend { up, stable, down }

class _InstantPhasesChart extends StatefulWidget {
  const _InstantPhasesChart({required this.points});

  final List<PhaseInstantPoint> points;

  @override
  State<_InstantPhasesChart> createState() => _InstantPhasesChartState();
}

class _InstantPhasesChartState extends State<_InstantPhasesChart> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xffe1e5dc)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) =>
                  _selectPoint(details.localPosition, constraints.biggest),
              child: CustomPaint(
                painter: _InstantPhasesChartPainter(
                  points: widget.points,
                  selectedIndex: _selectedIndex,
                  labelColor: Theme.of(context).colorScheme.onSurfaceVariant,
                  gridColor: const Color(0xffd7ddd3),
                ),
                child: const SizedBox.expand(),
              ),
            );
          },
        ),
      ),
    );
  }

  void _selectPoint(Offset position, Size size) {
    if (widget.points.length < 2) {
      return;
    }

    const yAxisWidth = _InstantPhasesChartPainter.yAxisWidth;
    const labelHeight = _InstantPhasesChartPainter.labelHeight;
    final chartHeight = size.height - labelHeight;
    final chartWidth = size.width - yAxisWidth;
    if (position.dy < 0 || position.dy > chartHeight) {
      return;
    }

    final ratio = ((position.dx - yAxisWidth) / chartWidth).clamp(0.0, 1.0);
    setState(() {
      _selectedIndex = ((widget.points.length - 1) * ratio).round();
    });
  }
}

class _InstantPhasesChartPainter extends CustomPainter {
  const _InstantPhasesChartPainter({
    required this.points,
    required this.selectedIndex,
    required this.labelColor,
    required this.gridColor,
  });

  final List<PhaseInstantPoint> points;
  final int? selectedIndex;
  final Color labelColor;
  final Color gridColor;

  static const labelHeight = 48.0;
  static const yAxisWidth = 56.0;
  static const _phase1Color = Color(0xffd97706);
  static const _phase2Color = Color(0xff2563eb);
  static const _phase3Color = Color(0xff0f766e);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) {
      return;
    }

    const yAxisLabelWidth = yAxisWidth - 12;
    final chartHeight = size.height - labelHeight;
    final chartWidth = size.width - yAxisWidth;
    final maxValue = points
        .map(
          (point) => math.max(
            point.phase1Va,
            math.max(point.phase2Va, point.phase3Va),
          ),
        )
        .reduce(math.max);
    final scaleMax = math.max(100.0, maxValue.toDouble());
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    const gridLineCount = 5;
    for (var index = 0; index < gridLineCount; index++) {
      final ratio = index / (gridLineCount - 1);
      final y = chartHeight * ratio;
      canvas.drawLine(Offset(yAxisWidth, y), Offset(size.width, y), gridPaint);
      final value = scaleMax * (1 - ratio);
      _drawLabel(
        canvas,
        _formatW(value),
        Offset(yAxisLabelWidth / 2, y - 6),
        align: TextAlign.right,
        width: yAxisLabelWidth,
      );
    }

    _drawVerticalGrid(canvas, chartWidth, chartHeight, yAxisWidth, gridPaint);

    _drawLine(
      canvas,
      points.map((p) => p.phase1Va).toList(),
      _phase1Color,
      chartWidth,
      chartHeight,
      yAxisWidth,
      scaleMax,
    );
    _drawLine(
      canvas,
      points.map((p) => p.phase2Va).toList(),
      _phase2Color,
      chartWidth,
      chartHeight,
      yAxisWidth,
      scaleMax,
    );
    _drawLine(
      canvas,
      points.map((p) => p.phase3Va).toList(),
      _phase3Color,
      chartWidth,
      chartHeight,
      yAxisWidth,
      scaleMax,
    );

    _drawSelectedPoint(canvas, chartWidth, chartHeight, yAxisWidth, scaleMax);
    _drawTimeLabels(canvas, chartHeight + 8, chartWidth, yAxisWidth);
    _drawLegend(canvas, size, chartHeight + 30);
  }

  void _drawSelectedPoint(
    Canvas canvas,
    double chartWidth,
    double chartHeight,
    double yAxisWidth,
    double scaleMax,
  ) {
    final index = selectedIndex;
    if (index == null || index < 0 || index >= points.length) {
      return;
    }

    final point = points[index];
    final x = yAxisWidth + chartWidth * index / (points.length - 1);
    final values = [point.phase1Va, point.phase2Va, point.phase3Va];
    final maxPhaseValue = values.reduce(math.max);
    final y = chartHeight - (maxPhaseValue / scaleMax) * (chartHeight - 8);

    final guidePaint = Paint()
      ..color = const Color(0xff111827).withValues(alpha: 0.35)
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(x, 0), Offset(x, chartHeight), guidePaint);

    final markerPaint = Paint()..color = const Color(0xff111827);
    canvas.drawCircle(Offset(x, y), 4.5, markerPaint);

    _drawTooltip(
      canvas,
      anchor: Offset(x, y),
      lines: [
        _formatTime(point.timestamp),
        'P1 ${_formatW(point.phase1Va.toDouble())}',
        'P2 ${_formatW(point.phase2Va.toDouble())}',
        'P3 ${_formatW(point.phase3Va.toDouble())}',
      ],
      chartWidth: chartWidth,
      yAxisWidth: yAxisWidth,
      chartHeight: chartHeight,
    );
  }

  void _drawLine(
    Canvas canvas,
    List<int> values,
    Color color,
    double chartWidth,
    double chartHeight,
    double yAxisWidth,
    double scaleMax,
  ) {
    final path = Path();
    for (var index = 0; index < values.length; index++) {
      final x = yAxisWidth + chartWidth * index / (values.length - 1);
      final y = chartHeight - (values[index] / scaleMax) * (chartHeight - 8);
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _drawLegend(Canvas canvas, Size size, double y) {
    final items = [
      ('P1', _phase1Color),
      ('P2', _phase2Color),
      ('P3', _phase3Color),
    ];
    var x = 46.0;
    for (final item in items) {
      final paint = Paint()..color = item.$2;
      canvas.drawCircle(Offset(x, y + 7), 4, paint);
      _drawLabel(canvas, item.$1, Offset(x + 20, y), width: 24);
      x += 52;
    }
  }

  void _drawTimeLabels(
    Canvas canvas,
    double y,
    double chartWidth,
    double yAxisWidth,
  ) {
    for (final marker in _timeMarkers(chartWidth, yAxisWidth)) {
      final x = marker.x.clamp(yAxisWidth + 24, yAxisWidth + chartWidth - 24);
      _drawLabel(
        canvas,
        _formatTime(marker.timestamp),
        Offset(x, y),
        width: 48,
      );
    }
  }

  void _drawVerticalGrid(
    Canvas canvas,
    double chartWidth,
    double chartHeight,
    double yAxisWidth,
    Paint paint,
  ) {
    for (final marker in _timeMarkers(chartWidth, yAxisWidth)) {
      canvas.drawLine(
        Offset(marker.x, 0),
        Offset(marker.x, chartHeight),
        paint,
      );
    }
  }

  List<({DateTime timestamp, double x})> _timeMarkers(
    double chartWidth,
    double yAxisWidth,
  ) {
    final first = points.first.timestamp;
    final last = points.last.timestamp;
    final totalSeconds = last.difference(first).inSeconds;
    if (totalSeconds <= 0) {
      return [(timestamp: first, x: yAxisWidth)];
    }

    final markers = <({DateTime timestamp, double x})>[];
    var cursor = _ceilToFiveMinutes(first);
    while (!cursor.isAfter(last)) {
      final elapsedSeconds = cursor.difference(first).inSeconds;
      final ratio = elapsedSeconds / totalSeconds;
      markers.add((timestamp: cursor, x: yAxisWidth + chartWidth * ratio));
      cursor = cursor.add(const Duration(minutes: 5));
    }

    if (markers.length >= 2) {
      return markers;
    }

    return [
      (timestamp: first, x: yAxisWidth),
      (timestamp: last, x: yAxisWidth + chartWidth),
    ];
  }

  DateTime _ceilToFiveMinutes(DateTime value) {
    final minuteRemainder = value.minute % 5;
    final alreadyAligned =
        minuteRemainder == 0 && value.second == 0 && value.millisecond == 0;
    if (alreadyAligned) {
      return DateTime(
        value.year,
        value.month,
        value.day,
        value.hour,
        value.minute,
      );
    }

    final minutesToAdd = minuteRemainder == 0 ? 5 : 5 - minuteRemainder;
    final rounded = DateTime(
      value.year,
      value.month,
      value.day,
      value.hour,
      value.minute,
    );
    return rounded.add(Duration(minutes: minutesToAdd));
  }

  void _drawLabel(
    Canvas canvas,
    String text,
    Offset center, {
    TextAlign align = TextAlign.center,
    double? width,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: labelColor, fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout(maxWidth: width ?? double.infinity);

    painter.paint(canvas, Offset(center.dx - painter.width / 2, center.dy));
  }

  void _drawTooltip(
    Canvas canvas, {
    required Offset anchor,
    required List<String> lines,
    required double chartWidth,
    required double yAxisWidth,
    required double chartHeight,
  }) {
    const width = 112.0;
    final height = 18.0 + lines.length * 16.0;
    var left = anchor.dx - width / 2;
    left = left.clamp(yAxisWidth + 4, yAxisWidth + chartWidth - width - 4);
    var top = anchor.dy - height - 12;
    if (top < 4) {
      top = anchor.dy + 12;
    }
    top = top.clamp(4.0, chartHeight - height - 4);

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, width, height),
      const Radius.circular(8),
    );
    canvas.drawRRect(
      rect,
      Paint()..color = const Color(0xff111827).withValues(alpha: 0.92),
    );

    for (var index = 0; index < lines.length; index++) {
      final painter = TextPainter(
        text: TextSpan(
          text: lines[index],
          style: TextStyle(
            color: Colors.white.withValues(alpha: index == 0 ? 0.94 : 0.82),
            fontSize: index == 0 ? 12 : 11,
            fontWeight: index == 0 ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: width - 16);
      painter.paint(canvas, Offset(left + 8, top + 8 + index * 16));
    }
  }

  String _formatW(double value) {
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)} kW';
    }
    return '${value.round()} W';
  }

  @override
  bool shouldRepaint(covariant _InstantPhasesChartPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.labelColor != labelColor ||
        oldDelegate.gridColor != gridColor;
  }
}

class _PhaseStat extends StatelessWidget {
  const _PhaseStat({
    required this.label,
    required this.averageVa,
    required this.trend,
  });

  final String label;
  final int averageVa;
  final _PhaseTrend trend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trendColor = switch (trend) {
      _PhaseTrend.up => const Color(0xffb91c1c),
      _PhaseTrend.stable => const Color(0xff4b5563),
      _PhaseTrend.down => const Color(0xff047857),
    };
    final trendIcon = switch (trend) {
      _PhaseTrend.up => Icons.trending_up,
      _PhaseTrend.stable => Icons.trending_flat,
      _PhaseTrend.down => Icons.trending_down,
    };
    final trendLabel = switch (trend) {
      _PhaseTrend.up => 'En hausse',
      _PhaseTrend.stable => 'Stable',
      _PhaseTrend.down => 'En baisse',
    };

    return SizedBox(
      width: math.min(MediaQuery.sizeOf(context).width - 32, 180),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xffe1e5dc)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${(averageVa / 1000).toStringAsFixed(2)} kW',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(trendIcon, size: 18, color: trendColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      trendLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: trendColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum HistoryRange { day, week }

class HistoryPage extends StatefulWidget {
  const HistoryPage({
    super.key,
    required this.apiBaseUrl,
    required this.repository,
  });

  final String apiBaseUrl;
  final LinkyRepository repository;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late LinkyRepository _repository;
  late Future<LinkySnapshot> _snapshotFuture;
  LinkyLoadState _loadState = const LinkyLoadState.connecting();
  var _range = HistoryRange.day;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _repository = widget.repository;
    _snapshotFuture = _loadSelectedDateFromCache();
  }

  void _reload() {
    setState(() {
      _snapshotFuture = _refreshSelectedDateFromNetwork();
    });
  }

  Future<LinkySnapshot> _loadSelectedDateFromCache() async {
    _updateLoadState(const LinkyLoadState.loadingPeriod('du cache local'));
    return _repository.fetchCachedDailySnapshot(_selectedDate);
  }

  Future<LinkySnapshot> _refreshSelectedDateFromNetwork() async {
    _updateLoadState(const LinkyLoadState.connecting());
    if (_repository is ApiLinkyRepository) {
      await (_repository as ApiLinkyRepository).checkHealth();
    }

    _updateLoadState(const LinkyLoadState.loadingPeriod('de la journée'));
    return _repository.fetchDailySnapshot(_selectedDate);
  }

  void _updateLoadState(LinkyLoadState state) {
    if (!mounted) {
      _loadState = state;
      return;
    }
    setState(() {
      _loadState = state;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked == null) {
      return;
    }

    setState(() {
      _selectedDate = picked;
      _snapshotFuture = _loadSelectedDateFromCache();
    });
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 720;

    return SafeArea(
      child: FutureBuilder<LinkySnapshot>(
        future: _snapshotFuture,
        builder: (context, snapshot) {
          return ListView(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 16 : 28,
              vertical: 20,
            ),
            children: [
              _HistoryHeader(onRefresh: _reload),
              const SizedBox(height: 14),
              _HistoryControls(
                range: _range,
                selectedDate: _selectedDate,
                onRangeChanged: (range) {
                  setState(() {
                    _range = range;
                  });
                },
                onPickDate: _pickDate,
              ),
              const SizedBox(height: 18),
              if (_range == HistoryRange.week)
                const _HistoryPlaceholder()
              else if (snapshot.connectionState != ConnectionState.done)
                SizedBox(
                  height: 220,
                  child: _LoadingView(message: _loadState.message),
                )
              else if (snapshot.hasError || !snapshot.hasData)
                _HistoryError(error: snapshot.error, onRetry: _reload)
              else
                _HistoryDayContent(snapshot: snapshot.data!),
            ],
          );
        },
      ),
    );
  }
}

class _HistoryHeader extends StatelessWidget {
  const _HistoryHeader({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Historique',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Consommation passée',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          onPressed: onRefresh,
          tooltip: 'Actualiser',
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }
}

class _HistoryControls extends StatelessWidget {
  const _HistoryControls({
    required this.range,
    required this.selectedDate,
    required this.onRangeChanged,
    required this.onPickDate,
  });

  final HistoryRange range;
  final DateTime selectedDate;
  final ValueChanged<HistoryRange> onRangeChanged;
  final VoidCallback onPickDate;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SegmentedButton<HistoryRange>(
          segments: const [
            ButtonSegment(
              value: HistoryRange.day,
              icon: Icon(Icons.calendar_today),
              label: Text('Jour'),
            ),
            ButtonSegment(
              value: HistoryRange.week,
              icon: Icon(Icons.view_week),
              label: Text('Semaine'),
            ),
          ],
          selected: {range},
          onSelectionChanged: (selection) {
            onRangeChanged(selection.first);
          },
        ),
        OutlinedButton.icon(
          onPressed: onPickDate,
          icon: const Icon(Icons.event),
          label: Text(_formatDate(selectedDate)),
        ),
      ],
    );
  }
}

class _HistoryDayContent extends StatelessWidget {
  const _HistoryDayContent({required this.snapshot});

  final LinkySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _HistoryStat(
              icon: Icons.bolt,
              label: 'Total',
              value: '${snapshot.dailyConsumptionKwh.toStringAsFixed(2)} kWh',
              color: snapshot.tempoToday.accent,
            ),
            _HistoryStat(
              icon: Icons.euro,
              label: 'Coût estimé',
              value: '${snapshot.dailyEnergyCostEuro.toStringAsFixed(2)} €',
              color: const Color(0xff0f766e),
            ),
            _HistoryStat(
              icon: Icons.wb_sunny,
              label: 'HP',
              value: '${snapshot.peakConsumptionKwh.toStringAsFixed(2)} kWh',
              color: const Color(0xffd97706),
            ),
            _HistoryStat(
              icon: Icons.nights_stay,
              label: 'HC',
              value: '${snapshot.offPeakConsumptionKwh.toStringAsFixed(2)} kWh',
              color: const Color(0xff2563eb),
            ),
          ],
        ),
        const SizedBox(height: 22),
        _SectionHeader(
          title: 'Répartition horaire',
          subtitle: 'Barres colorées selon le tarif Tempo',
          trailing: Text('24 h', style: theme.textTheme.labelLarge),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 280,
          child: _HourlyChart(values: snapshot.hourlyConsumption),
        ),
      ],
    );
  }
}

class _HistoryStat extends StatelessWidget {
  const _HistoryStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: math.min(MediaQuery.sizeOf(context).width - 32, 180),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xffe1e5dc)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      value,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryPlaceholder extends StatelessWidget {
  const _HistoryPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const _EmptyHistoryMessage(
      icon: Icons.construction,
      title: 'Vue semaine à venir',
      message:
          'La sélection est prête. Il faudra étendre l’API pour lire plusieurs fichiers journaliers.',
    );
  }
}

class _HistoryError extends StatelessWidget {
  const _HistoryError({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _EmptyHistoryMessage(
      icon: Icons.event_busy,
      title: 'Aucune donnée',
      message: error?.toString() ?? 'Impossible de charger cette période.',
      action: FilledButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh),
        label: const Text('Réessayer'),
      ),
    );
  }
}

class _EmptyHistoryMessage extends StatelessWidget {
  const _EmptyHistoryMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xffe1e5dc)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            Icon(icon, size: 42, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 10),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 12), action!],
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.snapshot,
    required this.apiBaseUrl,
    required this.onRefresh,
    required this.onChangeApiBaseUrl,
    required this.isRefreshing,
  });

  final LinkySnapshot snapshot;
  final String apiBaseUrl;
  final VoidCallback onRefresh;
  final ValueChanged<String> onChangeApiBaseUrl;
  final bool isRefreshing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SmartHouse',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Linky local - mis à jour à ${_formatTime(snapshot.timestamp)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isRefreshing) ...[
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
              const SizedBox(width: 10),
            ],
            IconButton.filledTonal(
              onPressed: isRefreshing ? null : onRefresh,
              tooltip: 'Actualiser',
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          onPressed: () => _showApiBaseUrlDialog(
            context: context,
            currentValue: apiBaseUrl,
            onSubmitted: onChangeApiBaseUrl,
          ),
          tooltip: 'Configurer',
          icon: const Icon(Icons.settings),
        ),
      ],
    );
  }
}

// ignore: unused_element
class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({required this.snapshot, required this.apiBaseUrl});

  final LinkySnapshot snapshot;
  final String apiBaseUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xffe7f4ee),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xffb7dec8)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: Color(0xff15803d)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Connecté à $apiBaseUrl - dernière mesure à ${_formatTime(snapshot.timestamp)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xff14532d),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodaySummaryHero extends StatelessWidget {
  const _TodaySummaryHero({required this.snapshot});

  final LinkySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = snapshot.tempoToday.accent;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 560;
            final label = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Aujourd'hui",
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            );
            final consumption = Column(
              crossAxisAlignment: compact
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.end,
              children: [
                Text(
                  '${snapshot.dailyConsumptionKwh.toStringAsFixed(2)} kWh',
                  style: theme.textTheme.displaySmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Coût estimé : ${snapshot.dailyEnergyCostEuro.toStringAsFixed(2)} €',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (_showLegacyMetrics)
                  Text(
                    'Coût estimé : ${snapshot.dailyEnergyCostEuro.toStringAsFixed(2)} €',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (_showLegacyMetrics) const SizedBox(height: 2),
                if (_showLegacyMetrics)
                  Text(
                    'Énergie seule depuis 00:00',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.78),
                    ),
                  ),
              ],
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [label, const SizedBox(height: 18), consumption],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: label),
                const SizedBox(width: 20),
                consumption,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TomorrowTempoCard extends StatelessWidget {
  const _TomorrowTempoCard({required this.snapshot});

  final LinkySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isKnown = snapshot.tempoTomorrow != TempoDayColor.unknown;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xffe1e5dc)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(
              isKnown ? Icons.event_available : Icons.event_note,
              color: isKnown
                  ? snapshot.tempoTomorrow.accent
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Demain',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isKnown
                        ? 'Jour ${snapshot.tempoTomorrow.label}'
                        : 'Couleur à connecter dans un second temps',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ignore: unused_element
class _CompactMetrics extends StatelessWidget {
  const _CompactMetrics({required this.snapshot});

  final LinkySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xffe1e5dc)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 520;
            final children = [
              _CompactMetricItem(
                icon: Icons.bolt,
                label: 'Puissance',
                value: '${snapshot.currentPowerKw.toStringAsFixed(2)} kW',
                detail: '${snapshot.powerVa} VA',
                color: const Color(0xffd97706),
              ),
              _CompactMetricItem(
                icon: Icons.calendar_month,
                label: 'Index compteur',
                value:
                    '${snapshot.monthlyConsumptionKwh.toStringAsFixed(1)} kWh',
                detail: 'Cumul total',
                color: const Color(0xff4f46e5),
              ),
            ];

            if (compact) {
              return Column(
                children: [
                  children.first,
                  const Divider(height: 18),
                  children.last,
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: children.first),
                const SizedBox(height: 42, child: VerticalDivider(width: 18)),
                Expanded(child: children.last),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CompactMetricItem extends StatelessWidget {
  const _CompactMetricItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
        Text(
          detail,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _PeakOffPeakCard extends StatelessWidget {
  const _PeakOffPeakCard({required this.snapshot});

  final LinkySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xffe1e5dc)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_showLegacyMetrics)
              Text(
                'HP / HC depuis 00:00',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            if (_showLegacyMetrics) const SizedBox(height: 4),
            if (_showLegacyMetrics)
              Text(
                'Répartition depuis 00:00, même si la couleur Tempo bascule à 06:00.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            if (_showLegacyMetrics) const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 520;
                final children = [
                  _TariffConsumptionPill(
                    icon: Icons.wb_sunny,
                    label: 'Heures pleines',
                    value:
                        '${snapshot.peakConsumptionKwh.toStringAsFixed(2)} kWh',
                    color: const Color(0xffd97706),
                  ),
                  _TariffConsumptionPill(
                    icon: Icons.nights_stay,
                    label: 'Heures creuses',
                    value:
                        '${snapshot.offPeakConsumptionKwh.toStringAsFixed(2)} kWh',
                    color: const Color(0xff2563eb),
                  ),
                ];

                if (compact) {
                  return Column(
                    children: [
                      children.first,
                      const SizedBox(height: 8),
                      children.last,
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: children.first),
                    const SizedBox(width: 8),
                    Expanded(child: children.last),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TariffConsumptionPill extends StatelessWidget {
  const _TariffConsumptionPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: math.min(MediaQuery.sizeOf(context).width - 32, 260),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xffe1e5dc)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 18),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(detail, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

// ignore: unused_element
class _PowerGauge extends StatelessWidget {
  const _PowerGauge({required this.snapshot});

  final LinkySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = snapshot.loadRatio.clamp(0.0, 1.0);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xff18221f),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
              title: 'Charge actuelle',
              subtitle: 'Comparée à la puissance souscrite',
              inverse: true,
              trailing: Icon(
                Icons.electric_meter,
                color: theme.colorScheme.primaryContainer,
              ),
            ),
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                minHeight: 16,
                value: ratio,
                backgroundColor: Colors.white.withValues(alpha: 0.16),
                color: ratio > 0.8
                    ? const Color(0xffef4444)
                    : const Color(0xff7dd3a5),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${snapshot.powerVa} VA sur ${snapshot.subscribedPowerKva * 1000} VA',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.82),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HourlyChart extends StatefulWidget {
  const _HourlyChart({required this.values});

  final List<HourlyConsumption> values;

  @override
  State<_HourlyChart> createState() => _HourlyChartState();
}

class _HourlyChartState extends State<_HourlyChart> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xffe1e5dc)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) =>
                  _selectBar(details.localPosition, constraints.biggest),
              child: CustomPaint(
                painter: _HourlyChartPainter(
                  values: widget.values,
                  selectedIndex: _selectedIndex,
                  barColor: Theme.of(context).colorScheme.primary,
                  gridColor: const Color(0xffd7ddd3),
                  labelColor: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                child: const SizedBox.expand(),
              ),
            );
          },
        ),
      ),
    );
  }

  void _selectBar(Offset position, Size size) {
    if (widget.values.isEmpty) {
      return;
    }

    const labelHeight = _HourlyChartPainter.labelHeight;
    const yAxisWidth = _HourlyChartPainter.yAxisWidth;
    final chartHeight = size.height - labelHeight;
    final chartWidth = size.width - yAxisWidth;
    if (position.dy < 0 || position.dy > chartHeight) {
      return;
    }

    final gap = size.width < 420 ? 3.0 : 6.0;
    final barWidth =
        (chartWidth - gap * (widget.values.length - 1)) / widget.values.length;
    final rawIndex = ((position.dx - yAxisWidth) / (barWidth + gap)).floor();
    final index = rawIndex.clamp(0, widget.values.length - 1);
    setState(() {
      _selectedIndex = index;
    });
  }
}

class _HourlyChartPainter extends CustomPainter {
  const _HourlyChartPainter({
    required this.values,
    required this.selectedIndex,
    required this.barColor,
    required this.gridColor,
    required this.labelColor,
  });

  final List<HourlyConsumption> values;
  final int? selectedIndex;
  final Color barColor;
  final Color gridColor;
  final Color labelColor;

  static const labelHeight = 24.0;
  static const yAxisWidth = 56.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) {
      return;
    }

    const yAxisLabelWidth = yAxisWidth - 12;
    final chartHeight = size.height - labelHeight;
    final chartWidth = size.width - yAxisWidth;
    final maxValue = values.map((e) => e.consumptionWh).reduce(math.max);
    final scaleMax = math.max(100.0, maxValue.toDouble());
    final paint = Paint();
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    const gridLineCount = 5;
    for (var index = 0; index < gridLineCount; index++) {
      final ratio = index / (gridLineCount - 1);
      final y = chartHeight * ratio;
      canvas.drawLine(Offset(yAxisWidth, y), Offset(size.width, y), gridPaint);
      final value = scaleMax * (1 - ratio);
      _drawLabel(
        canvas,
        _formatChartKwh(value),
        Offset(yAxisLabelWidth / 2, y - 6),
        align: TextAlign.right,
        width: yAxisLabelWidth,
      );
    }

    final gap = size.width < 420 ? 3.0 : 6.0;
    final barWidth = (chartWidth - gap * (values.length - 1)) / values.length;

    for (var index = 0; index < values.length; index++) {
      final entry = values[index];
      final normalized = entry.consumptionWh / scaleMax;
      final height = math.max(4.0, normalized * (chartHeight - 8));
      final left = yAxisWidth + index * (barWidth + gap);
      paint.color = _barColor(entry.tempoColor);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, chartHeight - height, barWidth, height),
        const Radius.circular(4),
      );
      canvas.drawRRect(rect, paint);

      if (entry.hour.hour % 3 == 0) {
        _drawLabel(
          canvas,
          '${entry.hour.hour}h',
          Offset(left + barWidth / 2, chartHeight + 8),
        );
      }
    }

    _drawSelectedBar(canvas, chartWidth, chartHeight, yAxisWidth, scaleMax);
  }

  void _drawSelectedBar(
    Canvas canvas,
    double chartWidth,
    double chartHeight,
    double yAxisWidth,
    double scaleMax,
  ) {
    final index = selectedIndex;
    if (index == null || index < 0 || index >= values.length) {
      return;
    }

    final gap = chartWidth + yAxisWidth < 420 ? 3.0 : 6.0;
    final barWidth = (chartWidth - gap * (values.length - 1)) / values.length;
    final entry = values[index];
    final height = math.max(
      4.0,
      (entry.consumptionWh / scaleMax) * (chartHeight - 8),
    );
    final left = yAxisWidth + index * (barWidth + gap);
    final centerX = left + barWidth / 2;
    final top = chartHeight - height;

    final markerPaint = Paint()
      ..color = const Color(0xff111827)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left - 1, top - 1, barWidth + 2, height + 2),
        const Radius.circular(5),
      ),
      markerPaint,
    );

    _drawTooltip(
      canvas,
      anchor: Offset(centerX, top),
      lines: [
        '${entry.hour.hour}h',
        _formatChartKwh(entry.consumptionWh.toDouble()),
        entry.tempoColor.label,
      ],
      chartWidth: chartWidth,
      yAxisWidth: yAxisWidth,
      chartHeight: chartHeight,
    );
  }

  void _drawLabel(
    Canvas canvas,
    String text,
    Offset center, {
    TextAlign align = TextAlign.center,
    double? width,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: labelColor, fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout(maxWidth: width ?? double.infinity);

    painter.paint(canvas, Offset(center.dx - painter.width / 2, center.dy));
  }

  void _drawTooltip(
    Canvas canvas, {
    required Offset anchor,
    required List<String> lines,
    required double chartWidth,
    required double yAxisWidth,
    required double chartHeight,
  }) {
    const width = 104.0;
    final height = 18.0 + lines.length * 16.0;
    var left = anchor.dx - width / 2;
    left = left.clamp(yAxisWidth + 4, yAxisWidth + chartWidth - width - 4);
    var top = anchor.dy - height - 12;
    if (top < 4) {
      top = anchor.dy + 12;
    }
    top = top.clamp(4.0, chartHeight - height - 4);

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, width, height),
      const Radius.circular(8),
    );
    canvas.drawRRect(
      rect,
      Paint()..color = const Color(0xff111827).withValues(alpha: 0.92),
    );

    for (var index = 0; index < lines.length; index++) {
      final painter = TextPainter(
        text: TextSpan(
          text: lines[index],
          style: TextStyle(
            color: Colors.white.withValues(alpha: index == 0 ? 0.94 : 0.82),
            fontSize: index == 0 ? 12 : 11,
            fontWeight: index == 0 ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: width - 16);
      painter.paint(canvas, Offset(left + 8, top + 8 + index * 16));
    }
  }

  String _formatChartKwh(double value) {
    final kwh = value / 1000;
    if (kwh >= 1) {
      return '${kwh.toStringAsFixed(1)} kWh';
    }
    return '${value.round()} Wh';
  }

  Color _barColor(TempoDayColor tempoColor) {
    return switch (tempoColor) {
      TempoDayColor.blue => const Color(0xff3279bd),
      TempoDayColor.white => const Color(0xff9ca3af),
      TempoDayColor.red => const Color(0xffc23b35),
      TempoDayColor.unknown => barColor,
    };
  }

  @override
  bool shouldRepaint(covariant _HourlyChartPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.barColor != barColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.labelColor != labelColor;
  }
}

// ignore: unused_element
class _TempoBand extends StatelessWidget {
  const _TempoBand({required this.snapshot});

  final LinkySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xffe1e5dc)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _TempoChip(label: 'Aujourd’hui', color: snapshot.tempoToday),
            _TempoChip(label: 'Demain', color: snapshot.tempoTomorrow),
            const Text('Option Tempo prête à connecter à l’API EDF/RTE'),
          ],
        ),
      ),
    );
  }
}

class _TempoChip extends StatelessWidget {
  const _TempoChip({required this.label, required this.color});

  final String label;
  final TempoDayColor color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: color.accent,
            shape: BoxShape.circle,
          ),
          child: const SizedBox(width: 12, height: 12),
        ),
        const SizedBox(width: 8),
        Text(
          '$label : ${color.label}',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    this.trailing,
    this.inverse = false,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;
  final bool inverse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = inverse ? Colors.white : theme.colorScheme.onSurface;
    final secondary = inverse
        ? Colors.white.withValues(alpha: 0.7)
        : theme.colorScheme.onSurfaceVariant;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(color: secondary),
              ),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 14),
          Text(message),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.apiBaseUrl,
    required this.error,
    required this.onRetry,
    required this.onChangeApiBaseUrl,
  });

  final String apiBaseUrl;
  final Object? error;
  final VoidCallback onRetry;
  final ValueChanged<String> onChangeApiBaseUrl;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 46),
            const SizedBox(height: 12),
            const Text(
              'Raspberry déconnecté',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Aucune donnée locale disponible. Appuie sur Réessayer pour interroger le Raspberry.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Adresse utilisée : $apiBaseUrl',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(
                error.toString(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _showApiBaseUrlDialog(
                context: context,
                currentValue: apiBaseUrl,
                onSubmitted: onChangeApiBaseUrl,
              ),
              icon: const Icon(Icons.settings),
              label: const Text('Changer l’adresse'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showApiBaseUrlDialog({
  required BuildContext context,
  required String currentValue,
  required ValueChanged<String> onSubmitted,
}) async {
  final controller = TextEditingController(text: currentValue);

  final result = await showDialog<String>(
    context: context,
    builder: (context) {
      String? testMessage;
      var isTesting = false;

      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Adresse du Raspberry'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'URL API',
                    hintText: 'http://192.168.1.42:8080',
                  ),
                  autofocus: true,
                  onSubmitted: (value) => Navigator.of(context).pop(value),
                ),
                if (testMessage != null) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      testMessage!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Annuler'),
              ),
              OutlinedButton.icon(
                onPressed: isTesting
                    ? null
                    : () async {
                        setDialogState(() {
                          isTesting = true;
                          testMessage = 'Test en cours...';
                        });

                        final normalized = _normalizeApiBaseUrlValue(
                          controller.text,
                        );
                        final message = await _testApiHealth(normalized);
                        setDialogState(() {
                          isTesting = false;
                          testMessage = message;
                        });
                      },
                icon: const Icon(Icons.wifi_find),
                label: const Text('Tester'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(controller.text),
                child: const Text('Enregistrer'),
              ),
            ],
          );
        },
      );
    },
  );

  controller.dispose();
  if (result == null || result.trim().isEmpty) {
    return;
  }
  onSubmitted(result);
}

String _normalizeApiBaseUrlValue(String value) {
  final trimmed = value.trim();
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed.replaceFirst(RegExp(r'/+$'), '');
  }
  return 'http://${trimmed.replaceFirst(RegExp(r'/+$'), '')}';
}

Future<String> _testApiHealth(String baseUrl) async {
  try {
    final response = await http
        .get(Uri.parse('$baseUrl/api/health'))
        .timeout(const Duration(seconds: 3));
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return 'Connexion OK sur $baseUrl';
    }
    return 'API trouvée, mais HTTP ${response.statusCode} sur /api/health';
  } catch (error) {
    return 'Connexion impossible à $baseUrl/api/health';
  }
}

String _formatTime(DateTime dateTime) {
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _formatDate(DateTime dateTime) {
  final day = dateTime.day.toString().padLeft(2, '0');
  final month = dateTime.month.toString().padLeft(2, '0');
  final year = dateTime.year.toString().padLeft(4, '0');
  return '$day/$month/$year';
}
