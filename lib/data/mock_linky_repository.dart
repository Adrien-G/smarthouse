import 'dart:async';

import '../models/linky_models.dart';

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
            isPeakHour: index >= 6 && index < 22,
          ),
      ],
    );
  }

  @override
  Future<LinkySnapshot> fetchDailySnapshot(DateTime date) async {
    return fetchCurrentSnapshot();
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
