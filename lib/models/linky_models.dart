import 'dart:math' as math;

import 'package:flutter/material.dart';

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
      readLinkyInt(current, key) - readLinkyInt(first, key),
    );
    return deltaWh / 1000 * pricePerKwh;
  }
}

class HourlyConsumption {
  const HourlyConsumption({
    required this.hour,
    required this.consumptionWh,
    required this.tempoColor,
    required this.isPeakHour,
  });

  final DateTime hour;
  final int consumptionWh;
  final TempoDayColor tempoColor;
  final bool isPeakHour;

  double get consumptionKwh => consumptionWh / 1000;
}

abstract class LinkyRepository {
  Future<LinkySnapshot> fetchCurrentSnapshot();
  Future<LinkySnapshot> fetchDailySnapshot(DateTime date);
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

class InstantConsumptionSnapshot {
  const InstantConsumptionSnapshot({
    required this.updatedAt,
    required this.points,
  });

  final DateTime updatedAt;
  final List<PhaseInstantPoint> points;

  PhaseInstantPoint? get latest => points.isEmpty ? null : points.last;
}

class LinkyLoadState {
  const LinkyLoadState.connecting() : message = 'Connexion au Raspberry...';

  const LinkyLoadState.loadingPeriod(String period)
    : message = 'Récupération $period...';

  final String message;
}

int readLinkyInt(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
