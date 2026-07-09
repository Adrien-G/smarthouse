import '../data/ingredient_units.dart';
import '../models/ingredient.dart';
import '../models/recipe.dart';
import '../data/pantry_ingredients.dart';

class RecipeTextParser {
  static Recipe parse({
    required String rawText,
    String? forcedName,
    String? forcedSteps,
  }) {
    final lines = rawText
        .split('\n')
        .map(_cleanLine)
        .where((line) => line.isNotEmpty)
        .toList();

    String name = forcedName?.trim() ?? '';
    final ingredientLines = <String>[];
    final stepLines = <String>[];

    var currentSection = _RecipeTextSection.unknown;

    for (final line in lines) {
      final normalizedLine = _normalizeText(line);

      if (_isIngredientsHeading(normalizedLine)) {
        currentSection = _RecipeTextSection.ingredients;
        continue;
      }

      if (_isStepsHeading(normalizedLine)) {
        currentSection = _RecipeTextSection.steps;
        continue;
      }

      if (name.isEmpty && currentSection == _RecipeTextSection.unknown) {
        name = _cleanTitle(line);
        continue;
      }

      if (currentSection == _RecipeTextSection.ingredients) {
        ingredientLines.add(line);
      } else if (currentSection == _RecipeTextSection.steps) {
        stepLines.add(line);
      } else if (_looksLikeIngredient(line)) {
        ingredientLines.add(line);
      } else {
        stepLines.add(line);
      }
    }

    if (name.isEmpty) {
      name = 'Nouvelle recette';
    }

    final ingredients = ingredientLines
        .map(parseIngredientLine)
        .where((ingredient) => ingredient.name.trim().isNotEmpty)
        .toList();

    final steps = forcedSteps != null && forcedSteps.trim().isNotEmpty
        ? forcedSteps.trim()
        : stepLines.join('\n');

    return Recipe(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      ingredients: ingredients,
      steps: steps.isEmpty ? 'À compléter.' : steps,
    );
  }

  static Ingredient parseIngredientLine(String rawLine) {
    final line = _cleanLine(rawLine);

    final quantityMatch = RegExp(
      r'^(\d+(?:[,.]\d+)?)\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(line);

    if (quantityMatch == null) {
      return Ingredient(
        name: line,
        category: guessCategory(line),
        includeInShoppingList: !shouldAutoExcludeFromShoppingList(line),
      );
    }

    final quantity = double.tryParse(
      quantityMatch.group(1)!.replaceAll(',', '.'),
    );

    var remainingText = quantityMatch.group(2)!.trim();

    final unitResult = _extractUnit(remainingText);

    String unit = unitResult.unit;
    remainingText = unitResult.remainingText;

    if (unit.isEmpty) {
      unit = 'unité';
    }

    final ingredientName = _cleanIngredientName(remainingText);

    return Ingredient(
      name: ingredientName,
      quantity: quantity,
      unit: ingredientUnits.contains(unit) ? unit : noIngredientUnit,
      category: guessCategory(ingredientName),
      includeInShoppingList: !shouldAutoExcludeFromShoppingList(ingredientName),
    );
  }

  static String guessCategory(String ingredientName) {
    final normalizedName = _normalizeIngredientForCategory(ingredientName);

    const fruitsAndVegetables = [
      'tomate',
      'salade',
      'laitue',
      'carotte',
      'courgette',
      'aubergine',
      'poivron',
      'concombre',
      'radis',
      'asperge',
      'fraise',
      'pomme',
      'poire',
      'banane',
      'citron',
      'orange',
      'oignon',
      'ail',
      'pomme de terre',
      'champignon',
      'poireau',
      'brocoli',
      'chou',
      'epinard',
      'haricot vert',
      'rhubarbe',
    ];

    const pantry = [
      'lait',
      'lait de coco',
      'oeuf',
      'œuf',
      'farine',
      'sucre',
      'sel',
      'poivre',
      'huile',
      'vinaigre',
      'riz',
      'pate',
      'pates',
      'semoule',
      'quinoa',
      'lentille',
      'pois chiche',
      'haricot rouge',
      'conserve',
      'chapelure',
      'moutarde',
      'mayonnaise',
      'ketchup',
      'sauce soja',
    ];

    const fresh = [
      'creme',
      'crème',
      'yaourt',
      'fromage',
      'parmesan',
      'beurre',
      'mozzarella',
      'emmental',
      'cheddar',
      'feta',
      'gruyere',
      'gruyère',
      'lardon',
      'pate feuilletee',
      'pâte feuilletée',
      'ricotta',
    ];

    const meatFish = [
      'poulet',
      'boeuf',
      'bœuf',
      'porc',
      'veau',
      'agneau',
      'jambon',
      'chorizo',
      'saumon',
      'thon',
      'cabillaud',
      'crevette',
      'poisson',
      'viande',
    ];

    const drinks = [
      'eau',
      'jus',
      'vin',
      'biere',
      'bière',
      'soda',
      'sirop',
      'boisson',
    ];

    const frozen = ['surgelé', 'surgele', 'glace'];

    if (_containsAnyIngredientTerm(normalizedName, frozen)) {
      return 'Surgelés';
    }

    if (_containsAnyIngredientTerm(normalizedName, fruitsAndVegetables)) {
      return 'Fruits & légumes';
    }

    if (_containsAnyIngredientTerm(normalizedName, fresh)) {
      return 'Frais';
    }

    if (_containsAnyIngredientTerm(normalizedName, pantry)) {
      return 'Épicerie';
    }

    if (_containsAnyIngredientTerm(normalizedName, meatFish)) {
      return 'Viandes / poissons';
    }

    if (_containsAnyIngredientTerm(normalizedName, drinks)) {
      return 'Boissons';
    }

    return 'Épicerie';
  }

  static bool _containsAnyIngredientTerm(
    String value,
    List<String> candidates,
  ) {
    return candidates.any((candidate) {
      final normalizedCandidate = _normalizeIngredientForCategory(candidate);

      return RegExp(
        '(^| )${RegExp.escape(normalizedCandidate)}( |s|x|\$)',
      ).hasMatch(value);
    });
  }

  static String _normalizeIngredientForCategory(String value) {
    return _normalizeText(value)
        .replaceAll('œ', 'oe')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool _looksLikeIngredient(String line) {
    final cleanedLine = _cleanLine(line);

    return RegExp(
      r'^\d+(?:[,.]\d+)?\s+',
      caseSensitive: false,
    ).hasMatch(cleanedLine);
  }

  static bool _isIngredientsHeading(String normalizedLine) {
    final heading = _normalizeHeading(normalizedLine);

    return heading == 'ingredients' ||
        heading == 'ingredient' ||
        heading.startsWith('ingredients pour') ||
        heading.startsWith('ingredient pour');
  }

  static bool _isStepsHeading(String normalizedLine) {
    final heading = _normalizeHeading(normalizedLine);

    return heading == 'preparation' ||
        heading == 'preparations' ||
        heading == 'etapes' ||
        heading == 'instructions' ||
        heading == 'procede' ||
        heading == 'procedure' ||
        heading == 'mode de preparation' ||
        heading == 'recette' ||
        heading.startsWith('preparation ') ||
        heading.startsWith('etapes ') ||
        heading.startsWith('instructions ');
  }

  static String _normalizeHeading(String value) {
    return value
        .trim()
        .replaceAll(RegExp(r'\s*:\s*$'), '')
        .replaceAll(RegExp(r'\s*-\s*$'), '')
        .trim();
  }

  static String _cleanLine(String line) {
    return line
        .trim()
        .replaceFirst(RegExp(r'^[-•*]\s*'), '')
        .replaceFirst(RegExp(r'^\d+[.)]\s*'), '')
        .trim();
  }

  static String _cleanTitle(String line) {
    return line
        .replaceFirst(RegExp(r'^(titre|nom)\s*:\s*', caseSensitive: false), '')
        .trim();
  }

  static String _cleanIngredientName(String value) {
    return value
        .trim()
        .replaceFirst(
          RegExp(
            r"^(de\s+l[’']\s*|d[’']\s*|de\s+la\s+|de\s+l\s+|du\s+|des\s+|de\s+)",
            caseSensitive: false,
          ),
          '',
        )
        .replaceFirst(RegExp(r"^l[’']\s*", caseSensitive: false), '')
        .trim();
  }

  static _UnitParseResult _extractUnit(String text) {
    final normalizedText = _normalizeText(text);

    final aliases = <_UnitAlias>[
      _UnitAlias('cuilleres a soupe', 'c. à soupe'),
      _UnitAlias('cuillere a soupe', 'c. à soupe'),
      _UnitAlias('c. a soupe', 'c. à soupe'),
      _UnitAlias('c a soupe', 'c. à soupe'),
      _UnitAlias('cas', 'c. à soupe'),
      _UnitAlias('càs', 'c. à soupe'),
      _UnitAlias('cuilleres a cafe', 'c. à café'),
      _UnitAlias('cuillere a cafe', 'c. à café'),
      _UnitAlias('c. a cafe', 'c. à café'),
      _UnitAlias('c a cafe', 'c. à café'),
      _UnitAlias('cac', 'c. à café'),
      _UnitAlias('càc', 'c. à café'),
      _UnitAlias('kilogrammes', 'kg'),
      _UnitAlias('kilogramme', 'kg'),
      _UnitAlias('kilos', 'kg'),
      _UnitAlias('kilo', 'kg'),
      _UnitAlias('kg', 'kg'),
      _UnitAlias('grammes', 'g'),
      _UnitAlias('gramme', 'g'),
      _UnitAlias('gr', 'g'),
      _UnitAlias('g', 'g'),
      _UnitAlias('milligrammes', 'mg'),
      _UnitAlias('milligramme', 'mg'),
      _UnitAlias('mg', 'mg'),
      _UnitAlias('litres', 'L'),
      _UnitAlias('litre', 'L'),
      _UnitAlias('l', 'L'),
      _UnitAlias('centilitres', 'cl'),
      _UnitAlias('centilitre', 'cl'),
      _UnitAlias('cl', 'cl'),
      _UnitAlias('millilitres', 'ml'),
      _UnitAlias('millilitre', 'ml'),
      _UnitAlias('ml', 'ml'),
      _UnitAlias('unites', 'unité'),
      _UnitAlias('unite', 'unité'),
      _UnitAlias('unités', 'unité'),
      _UnitAlias('unité', 'unité'),
      _UnitAlias('pieces', 'pièce'),
      _UnitAlias('piece', 'pièce'),
      _UnitAlias('pièces', 'pièce'),
      _UnitAlias('pièce', 'pièce'),
      _UnitAlias('pincees', 'pincée'),
      _UnitAlias('pincee', 'pincée'),
      _UnitAlias('pincées', 'pincée'),
      _UnitAlias('pincée', 'pincée'),
      _UnitAlias('gousses', 'gousse'),
      _UnitAlias('gousse', 'gousse'),
      _UnitAlias('tranches', 'tranche'),
      _UnitAlias('tranche', 'tranche'),
      _UnitAlias('sachets', 'sachet'),
      _UnitAlias('sachet', 'sachet'),
      _UnitAlias('boites', 'boîte'),
      _UnitAlias('boite', 'boîte'),
      _UnitAlias('boîtes', 'boîte'),
      _UnitAlias('boîte', 'boîte'),
      _UnitAlias('pots', 'pot'),
      _UnitAlias('pot', 'pot'),
    ]..sort((a, b) => b.alias.length.compareTo(a.alias.length));

    for (final alias in aliases) {
      if (normalizedText == alias.alias ||
          normalizedText.startsWith('${alias.alias} ')) {
        final remainingText = text.substring(
          _matchingPrefixLength(text, alias.alias),
        );

        return _UnitParseResult(
          unit: alias.unit,
          remainingText: remainingText.trim(),
        );
      }
    }

    return _UnitParseResult(unit: '', remainingText: text);
  }

  static int _matchingPrefixLength(
    String originalText,
    String normalizedAlias,
  ) {
    final words = originalText.trim().split(RegExp(r'\s+'));
    final buffer = StringBuffer();

    for (int index = 0; index < words.length; index++) {
      if (buffer.isNotEmpty) {
        buffer.write(' ');
      }

      buffer.write(words[index]);

      if (_normalizeText(buffer.toString()) == normalizedAlias) {
        return buffer.toString().length;
      }
    }

    return normalizedAlias.length;
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
        .replaceAll('ö', 'o')
        .replaceAll('ç', 'c')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'\.$'), '');
  }
}

enum _RecipeTextSection { unknown, ingredients, steps }

class _UnitAlias {
  const _UnitAlias(this.alias, this.unit);

  final String alias;
  final String unit;
}

class _UnitParseResult {
  const _UnitParseResult({required this.unit, required this.remainingText});

  final String unit;
  final String remainingText;
}
