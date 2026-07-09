const List<String> defaultPantryIngredientNames = [
  'sel',
  'poivre',
  'huile',
  'huile d’olive',
  'huile de tournesol',
  'vinaigre',
  'sucre',
  'farine',
  'levure',
  'épice',
  'épices',
  'paprika',
  'curry',
  'cumin',
  'cannelle',
  'muscade',
  'thym',
  'laurier',
  'origan',
  'herbes de provence',
];

bool shouldAutoExcludeFromShoppingList(String ingredientName) {
  return shouldExcludeFromShoppingList(
    ingredientName: ingredientName,
    pantryIngredientNames: defaultPantryIngredientNames,
  );
}

bool shouldExcludeFromShoppingList({
  required String ingredientName,
  required Iterable<String> pantryIngredientNames,
}) {
  final normalizedName = _normalizePantryText(ingredientName);

  return pantryIngredientNames.any((pantryIngredient) {
    final normalizedPantryIngredient = _normalizePantryText(pantryIngredient);

    if (normalizedName.isEmpty || normalizedPantryIngredient.isEmpty) {
      return false;
    }

    return _containsAsWords(
      value: normalizedName,
      searchedValue: normalizedPantryIngredient,
    );
  });
}

List<String> normalizePantryIngredientNames(Iterable<String> ingredientNames) {
  final uniqueNames = <String, String>{};

  for (final ingredientName in ingredientNames) {
    final trimmedName = ingredientName.trim();
    final normalizedName = _normalizePantryText(trimmedName);

    if (trimmedName.isEmpty || normalizedName.isEmpty) {
      continue;
    }

    uniqueNames[normalizedName] = trimmedName;
  }

  final sortedNames = uniqueNames.values.toList()
    ..sort((a, b) {
      return _normalizePantryText(a).compareTo(_normalizePantryText(b));
    });

  return sortedNames;
}

bool _containsAsWords({required String value, required String searchedValue}) {
  final normalizedValue = ' ${_singularizeWords(value)} ';
  final normalizedSearchedValue = ' ${_singularizeWords(searchedValue)} ';

  return normalizedValue.contains(normalizedSearchedValue);
}

String _singularizeWords(String value) {
  return value
      .split(' ')
      .map((word) {
        if (word.length <= 3) {
          return word;
        }

        if (word.endsWith('aux')) {
          return '${word.substring(0, word.length - 3)}al';
        }

        if (word.endsWith('s') || word.endsWith('x')) {
          return word.substring(0, word.length - 1);
        }

        return word;
      })
      .join(' ');
}

String _normalizePantryText(String value) {
  return value
      .toLowerCase()
      .trim()
      .replaceAll('œ', 'oe')
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
      .replaceAll('ö', 'o')
      .replaceAll('ç', 'c')
      .replaceAll(RegExp(r"[’']"), ' ')
      .replaceAll(RegExp(r'[^a-z0-9\s-]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
