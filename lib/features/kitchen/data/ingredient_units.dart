const String noIngredientUnit = '';

const List<String> ingredientUnits = [
  noIngredientUnit,
  'mg',
  'g',
  'kg',
  'ml',
  'cl',
  'L',
  'unité',
  'pièce',
  'c. à café',
  'c. à soupe',
  'pincée',
  'gousse',
  'tranche',
  'sachet',
  'boîte',
  'pot',
];

String getIngredientUnitLabel(String unit) {
  if (unit.isEmpty) {
    return 'Sans unité';
  }

  return unit;
}
