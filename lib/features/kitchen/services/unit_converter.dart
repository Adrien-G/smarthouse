class NormalizedUnit {
  const NormalizedUnit({
    required this.groupKey,
    required this.displayUnit,
    required this.multiplierToBase,
    required this.kind,
  });

  final String groupKey;
  final String displayUnit;
  final double multiplierToBase;
  final UnitKind kind;

  double convertToBase(double quantity) {
    return quantity * multiplierToBase;
  }
}

enum UnitKind { weight, volume, count, custom, none }

class UnitConverter {
  static NormalizedUnit normalize(String unit) {
    final originalUnit = unit.trim();
    final normalizedUnit = _normalizeText(originalUnit);

    if (normalizedUnit.isEmpty) {
      return const NormalizedUnit(
        groupKey: 'none',
        displayUnit: '',
        multiplierToBase: 1,
        kind: UnitKind.none,
      );
    }

    final knownUnit = _knownUnits[normalizedUnit];

    if (knownUnit != null) {
      return knownUnit;
    }

    final customDisplayUnit = _getCustomDisplayUnit(
      normalizedUnit: normalizedUnit,
      originalUnit: originalUnit,
    );

    return NormalizedUnit(
      groupKey: 'custom:${_normalizeText(customDisplayUnit)}',
      displayUnit: customDisplayUnit,
      multiplierToBase: 1,
      kind: UnitKind.custom,
    );
  }

  static String formatBaseQuantity(NormalizedUnit unit, double baseQuantity) {
    switch (unit.kind) {
      case UnitKind.weight:
        return _formatWeight(baseQuantity);
      case UnitKind.volume:
        return _formatVolume(baseQuantity);
      case UnitKind.count:
        return _formatNumber(baseQuantity);
      case UnitKind.custom:
        return '${_formatNumber(baseQuantity)} ${unit.displayUnit}'.trim();
      case UnitKind.none:
        return _formatNumber(baseQuantity);
    }
  }

  static final Map<String, NormalizedUnit> _knownUnits = {
    // Poids : base = gramme
    'mg': NormalizedUnit(
      groupKey: 'weight',
      displayUnit: 'g',
      multiplierToBase: 0.001,
      kind: UnitKind.weight,
    ),
    'milligramme': NormalizedUnit(
      groupKey: 'weight',
      displayUnit: 'g',
      multiplierToBase: 0.001,
      kind: UnitKind.weight,
    ),
    'milligrammes': NormalizedUnit(
      groupKey: 'weight',
      displayUnit: 'g',
      multiplierToBase: 0.001,
      kind: UnitKind.weight,
    ),
    'g': NormalizedUnit(
      groupKey: 'weight',
      displayUnit: 'g',
      multiplierToBase: 1,
      kind: UnitKind.weight,
    ),
    'gr': NormalizedUnit(
      groupKey: 'weight',
      displayUnit: 'g',
      multiplierToBase: 1,
      kind: UnitKind.weight,
    ),
    'gramme': NormalizedUnit(
      groupKey: 'weight',
      displayUnit: 'g',
      multiplierToBase: 1,
      kind: UnitKind.weight,
    ),
    'grammes': NormalizedUnit(
      groupKey: 'weight',
      displayUnit: 'g',
      multiplierToBase: 1,
      kind: UnitKind.weight,
    ),
    'kg': NormalizedUnit(
      groupKey: 'weight',
      displayUnit: 'g',
      multiplierToBase: 1000,
      kind: UnitKind.weight,
    ),
    'kgs': NormalizedUnit(
      groupKey: 'weight',
      displayUnit: 'g',
      multiplierToBase: 1000,
      kind: UnitKind.weight,
    ),
    'kilo': NormalizedUnit(
      groupKey: 'weight',
      displayUnit: 'g',
      multiplierToBase: 1000,
      kind: UnitKind.weight,
    ),
    'kilos': NormalizedUnit(
      groupKey: 'weight',
      displayUnit: 'g',
      multiplierToBase: 1000,
      kind: UnitKind.weight,
    ),
    'kilogramme': NormalizedUnit(
      groupKey: 'weight',
      displayUnit: 'g',
      multiplierToBase: 1000,
      kind: UnitKind.weight,
    ),
    'kilogrammes': NormalizedUnit(
      groupKey: 'weight',
      displayUnit: 'g',
      multiplierToBase: 1000,
      kind: UnitKind.weight,
    ),

    // Volume : base = millilitre
    'ml': NormalizedUnit(
      groupKey: 'volume',
      displayUnit: 'ml',
      multiplierToBase: 1,
      kind: UnitKind.volume,
    ),
    'millilitre': NormalizedUnit(
      groupKey: 'volume',
      displayUnit: 'ml',
      multiplierToBase: 1,
      kind: UnitKind.volume,
    ),
    'millilitres': NormalizedUnit(
      groupKey: 'volume',
      displayUnit: 'ml',
      multiplierToBase: 1,
      kind: UnitKind.volume,
    ),
    'cl': NormalizedUnit(
      groupKey: 'volume',
      displayUnit: 'ml',
      multiplierToBase: 10,
      kind: UnitKind.volume,
    ),
    'centilitre': NormalizedUnit(
      groupKey: 'volume',
      displayUnit: 'ml',
      multiplierToBase: 10,
      kind: UnitKind.volume,
    ),
    'centilitres': NormalizedUnit(
      groupKey: 'volume',
      displayUnit: 'ml',
      multiplierToBase: 10,
      kind: UnitKind.volume,
    ),
    'l': NormalizedUnit(
      groupKey: 'volume',
      displayUnit: 'ml',
      multiplierToBase: 1000,
      kind: UnitKind.volume,
    ),
    'litre': NormalizedUnit(
      groupKey: 'volume',
      displayUnit: 'ml',
      multiplierToBase: 1000,
      kind: UnitKind.volume,
    ),
    'litres': NormalizedUnit(
      groupKey: 'volume',
      displayUnit: 'ml',
      multiplierToBase: 1000,
      kind: UnitKind.volume,
    ),

    // Quantité simple
    'u': NormalizedUnit(
      groupKey: 'count',
      displayUnit: '',
      multiplierToBase: 1,
      kind: UnitKind.count,
    ),
    'unite': NormalizedUnit(
      groupKey: 'count',
      displayUnit: '',
      multiplierToBase: 1,
      kind: UnitKind.count,
    ),
    'unites': NormalizedUnit(
      groupKey: 'count',
      displayUnit: '',
      multiplierToBase: 1,
      kind: UnitKind.count,
    ),
    'piece': NormalizedUnit(
      groupKey: 'count',
      displayUnit: '',
      multiplierToBase: 1,
      kind: UnitKind.count,
    ),
    'pieces': NormalizedUnit(
      groupKey: 'count',
      displayUnit: '',
      multiplierToBase: 1,
      kind: UnitKind.count,
    ),
    'pc': NormalizedUnit(
      groupKey: 'count',
      displayUnit: '',
      multiplierToBase: 1,
      kind: UnitKind.count,
    ),
    'pcs': NormalizedUnit(
      groupKey: 'count',
      displayUnit: '',
      multiplierToBase: 1,
      kind: UnitKind.count,
    ),
  };

  static String _getCustomDisplayUnit({
    required String normalizedUnit,
    required String originalUnit,
  }) {
    if (_tablespoonAliases.contains(normalizedUnit)) {
      return 'c. à soupe';
    }

    if (_teaspoonAliases.contains(normalizedUnit)) {
      return 'c. à café';
    }

    if (normalizedUnit == 'pincee' || normalizedUnit == 'pincees') {
      return 'pincée';
    }

    if (normalizedUnit == 'gousse' || normalizedUnit == 'gousses') {
      return 'gousse';
    }

    return originalUnit;
  }

  static const Set<String> _tablespoonAliases = {
    'cas',
    'c a s',
    'c. a soupe',
    'c a soupe',
    'cuillere a soupe',
    'cuilleres a soupe',
  };

  static const Set<String> _teaspoonAliases = {
    'cac',
    'c a c',
    'c. a cafe',
    'c a cafe',
    'cuillere a cafe',
    'cuilleres a cafe',
  };

  static String _formatWeight(double grams) {
    if (grams >= 1000) {
      return '${_formatNumber(grams / 1000)} kg';
    }

    if (grams > 0 && grams < 1) {
      return '${_formatNumber(grams * 1000)} mg';
    }

    return '${_formatNumber(grams)} g';
  }

  static String _formatVolume(double milliliters) {
    if (milliliters >= 1000) {
      return '${_formatNumber(milliliters / 1000)} L';
    }

    if (milliliters >= 100) {
      return '${_formatNumber(milliliters / 10)} cl';
    }

    return '${_formatNumber(milliliters)} ml';
  }

  static String _formatNumber(double value) {
    String formattedValue;

    if (value == value.roundToDouble()) {
      formattedValue = value.toInt().toString();
    } else {
      formattedValue = value
          .toStringAsFixed(2)
          .replaceAll(RegExp(r'0+$'), '')
          .replaceAll(RegExp(r'\.$'), '');
    }

    return formattedValue.replaceAll('.', ',');
  }

  static String _normalizeText(String value) {
    return value
        .toLowerCase()
        .trim()
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('ë', 'e')
        .replaceAll('à', 'a')
        .replaceAll('â', 'a')
        .replaceAll('ù', 'u')
        .replaceAll('û', 'u')
        .replaceAll('î', 'i')
        .replaceAll('ï', 'i')
        .replaceAll('ô', 'o')
        .replaceAll('ç', 'c')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'\.$'), '');
  }
}
