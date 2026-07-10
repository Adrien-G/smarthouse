import 'dart:convert';

import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../models/ingredient.dart';
import '../models/recipe.dart';
import 'recipe_text_parser.dart';

class RecipeUrlImporter {
  static Future<Recipe> importFromUrl(String url) async {
    final uri = Uri.tryParse(url.trim());

    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw const RecipeUrlImportException('Le lien ne semble pas valide.');
    }

    final response = await http.get(
      uri,
      headers: const {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RecipeUrlImportException(
        'Impossible de charger la page. Code HTTP : ${response.statusCode}.',
      );
    }

    return importFromHtml(response.body).copyWith(sourceUrl: uri.toString());
  }

  static Recipe importFromHtml(String rawHtml) {
    final document = html_parser.parse(rawHtml);
    final jsonLdRecipe = _tryBuildRecipeFromJsonLd(document);

    if (jsonLdRecipe != null) {
      return jsonLdRecipe;
    }

    final articleRecipe = _tryBuildRecipeFromArticle(document);

    if (articleRecipe != null) {
      return articleRecipe;
    }

    throw const RecipeUrlImportException(
      'Je n’ai pas trouvé de recette structurée sur cette page. '
      'Tu peux utiliser le mode “Coller une recette” à la place.',
    );
  }

  static Recipe? _tryBuildRecipeFromJsonLd(html_dom.Document document) {
    final scripts = document.querySelectorAll('script').where((script) {
      final type = script.attributes['type']?.toLowerCase() ?? '';

      return type.contains('ld+json');
    }).toList();

    for (final script in scripts) {
      final rawJson = script.text.trim();

      if (rawJson.isEmpty) {
        continue;
      }

      dynamic decoded;

      try {
        decoded = jsonDecode(rawJson);
      } catch (error) {
        // Certains sites ont plusieurs scripts JSON-LD.
        // Si l’un est invalide, on essaie les suivants.
        continue;
      }

      final recipeData = _findRecipeData(decoded);

      if (recipeData == null) {
        continue;
      }

      return _buildRecipeFromJsonLd(recipeData);
    }

    return null;
  }

  static Recipe? _tryBuildRecipeFromArticle(html_dom.Document document) {
    final name = _findArticleTitle(document);
    final ingredientTexts = _extractArticleIngredientLines(document);
    final stepTexts = _extractArticleInstructionLines(document);

    if (ingredientTexts.isEmpty || stepTexts.isEmpty) {
      return null;
    }

    final ingredients = ingredientTexts
        .map(RecipeTextParser.parseIngredientLine)
        .where((ingredient) => ingredient.name.trim().isNotEmpty)
        .toList();

    return Recipe(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name ?? 'Nouvelle recette',
      ingredients: ingredients.isEmpty
          ? [const Ingredient(name: 'À compléter')]
          : ingredients,
      steps: stepTexts.join('\n'),
      prepTimeMinutes: _readArticleMinutes(document, ['preparation', 'prep']),
      cookTimeMinutes: _readArticleMinutes(document, ['cuisson', 'cook']),
    );
  }

  static String? _findArticleTitle(html_dom.Document document) {
    final titleSelectors = ['h1', 'meta[property="og:title"]', 'title'];

    for (final selector in titleSelectors) {
      final element = document.querySelector(selector);
      final text = selector.startsWith('meta')
          ? element?.attributes['content']
          : element?.text;
      final cleaned = _cleanArticleText(text ?? '');

      if (cleaned.isNotEmpty) {
        return cleaned.replaceAll(RegExp(r'\s+[-|]\s+.*$'), '').trim();
      }
    }

    return null;
  }

  static List<String> _extractArticleIngredientLines(
    html_dom.Document document,
  ) {
    final lines = <String>[];
    var isInIngredientsSection = false;

    for (final text in _articleTextLines(document)) {
      final normalizedText = _normalizeArticleText(text);

      if (text.isEmpty) {
        continue;
      }

      if (_isIngredientHeading(normalizedText)) {
        isInIngredientsSection = true;
        continue;
      }

      if (isInIngredientsSection &&
          (_isPreparationHeading(normalizedText) ||
              _cleanNumberedStep(text) != null)) {
        break;
      }

      if (!isInIngredientsSection) {
        continue;
      }

      lines.addAll(_splitArticleIngredientText(text));
    }

    return lines;
  }

  static List<String> _extractArticleInstructionLines(
    html_dom.Document document,
  ) {
    final steps = <String>[];
    var isInPreparationSection = false;

    for (final text in _articleTextLines(document)) {
      final normalizedText = _normalizeArticleText(text);

      if (text.isEmpty) {
        continue;
      }

      final numberedStep = _cleanNumberedStep(text);

      if (numberedStep != null) {
        steps.add(numberedStep);
        isInPreparationSection = true;
        continue;
      }

      if (_isPreparationHeading(normalizedText)) {
        isInPreparationSection = true;
        continue;
      }

      if (!isInPreparationSection) {
        continue;
      }

      if (_isNonRecipeSection(normalizedText)) {
        break;
      }

      if (_looksLikeInstruction(text)) {
        steps.add(text);
      }
    }

    return _deduplicateArticleLines(steps);
  }

  static List<String> _articleTextLines(html_dom.Document document) {
    final root =
        document.querySelector('article') ??
        document.querySelector('main') ??
        document.body;
    final lines = <String>[];

    if (root != null) {
      for (final element in root.querySelectorAll(
        'h1,h2,h3,h4,h5,p,li,strong,b,span,div',
      )) {
        if (!_isUsefulArticleTextElement(element)) {
          continue;
        }

        final text = _cleanArticleText(element.text);

        if (_isUsefulArticleLine(text)) {
          lines.add(text);
        }
      }
    }

    lines.addAll(_bodyTextLines(document));

    return _deduplicateArticleLines(lines);
  }

  static bool _isUsefulArticleTextElement(html_dom.Element element) {
    final tag = element.localName;

    if (tag == 'div' &&
        element.querySelector('h1,h2,h3,h4,h5,p,li,div') != null) {
      return false;
    }

    if ((tag == 'span' || tag == 'strong' || tag == 'b') &&
        element.parent?.localName == 'p') {
      return false;
    }

    return true;
  }

  static Iterable<String> _bodyTextLines(html_dom.Document document) {
    final bodyText = document.body?.text ?? '';

    return const LineSplitter()
        .convert(bodyText)
        .map(_cleanArticleText)
        .where(_isUsefulArticleLine);
  }

  static bool _isUsefulArticleLine(String value) {
    if (value.length < 3 || value.length > 600) {
      return false;
    }

    return true;
  }

  static List<String> _deduplicateArticleLines(Iterable<String> lines) {
    final seen = <String>{};
    final result = <String>[];

    for (final line in lines.map(_cleanArticleText)) {
      if (line.isEmpty) {
        continue;
      }

      final normalizedLine = _normalizeArticleText(line);

      if (seen.add(normalizedLine)) {
        result.add(line);
      }
    }

    return result;
  }

  static List<String> _splitArticleIngredientText(String value) {
    var text = value
        .replaceFirst(
          RegExp(r'^pour [^,.:]+[,.:]\s*', caseSensitive: false),
          '',
        )
        .replaceFirst(
          RegExp(
            r'^la [^,.:]+(?:nécessite|necessite|demande)\s*',
            caseSensitive: false,
          ),
          '',
        )
        .replaceFirst(
          RegExp(r'^(?:prévoyez|prevoyez|comptez)\s*', caseSensitive: false),
          '',
        )
        .trim();

    final parts = text
        .split(RegExp(r'\s*,\s*|\s+;\s+|\s+ et \s+'))
        .map(_cleanArticleText)
        .where((part) => part.isNotEmpty)
        .toList();

    return parts.length <= 1 ? [text] : parts;
  }

  static String? _cleanNumberedStep(String value) {
    final match = RegExp(
      r'^\s*(?:étape|etape)\s*\d+\s*[:.-]\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(value);

    return match?.group(1)?.trim();
  }

  static bool _looksLikeInstruction(String value) {
    final normalizedValue = _normalizeArticleText(value);

    return RegExp(
      r'\b(faire|faites|ajouter|ajoutez|melanger|mélanger|melangez|mélangez|couper|coupez|cuire|cuisez|enfourner|enfournez|verser|versez|incorporer|incorporez|laisser|laissez|servez|servir|disposez|disposer|parsemer|parsemez|ecraser|écraser|ecrasez|écrasez|eplucher|éplucher|epluchez|épluchez|revenir|preparer|préparer|preparez|préparez)\b',
    ).hasMatch(normalizedValue);
  }

  static bool _isIngredientHeading(String value) {
    return value == 'ingredients' ||
        value.startsWith('ingredients ') ||
        value.contains('ingredients pour');
  }

  static bool _isPreparationHeading(String value) {
    return value == 'preparation' ||
        value == 'préparation' ||
        value.startsWith('preparation ') ||
        value.startsWith('préparation ') ||
        value.startsWith('etapes') ||
        value.startsWith('étapes');
  }

  static bool _isNonRecipeSection(String value) {
    return value.startsWith('astuce') ||
        value.startsWith('conseil') ||
        value.startsWith('variante') ||
        value.startsWith('note') ||
        value.startsWith('questions') ||
        value.startsWith('faq');
  }

  static int? _readArticleMinutes(
    html_dom.Document document,
    List<String> keywords,
  ) {
    final text = _normalizeArticleText(document.body?.text ?? '');

    for (final keyword in keywords) {
      final match = RegExp(
        '(\\d{1,3})\\s*(?:min|mn|minute|minutes)\\s+(?:de\\s+)?$keyword',
      ).firstMatch(text);

      if (match != null) {
        return int.tryParse(match.group(1) ?? '');
      }

      final reverseMatch = RegExp(
        '$keyword\\s*:?\\s*(\\d{1,3})\\s*(?:min|mn|minute|minutes)',
      ).firstMatch(text);

      if (reverseMatch != null) {
        return int.tryParse(reverseMatch.group(1) ?? '');
      }
    }

    return null;
  }

  static String _cleanArticleText(String value) {
    return value
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('\u00a0', ' ')
        .trim();
  }

  static String _normalizeArticleText(String value) {
    final buffer = StringBuffer();

    for (final rune in _cleanArticleText(value).toLowerCase().runes) {
      switch (rune) {
        case 0x00E0:
        case 0x00E2:
        case 0x00E4:
          buffer.write('a');
        case 0x00E7:
          buffer.write('c');
        case 0x00E8:
        case 0x00E9:
        case 0x00EA:
        case 0x00EB:
          buffer.write('e');
        case 0x00EE:
        case 0x00EF:
          buffer.write('i');
        case 0x00F4:
        case 0x00F6:
          buffer.write('o');
        case 0x0153:
          buffer.write('oe');
        case 0x00F9:
        case 0x00FB:
        case 0x00FC:
          buffer.write('u');
        default:
          buffer.writeCharCode(rune);
      }
    }

    return buffer.toString();
  }

  static Map<String, dynamic>? _findRecipeData(dynamic value) {
    if (value is List) {
      for (final item in value) {
        final result = _findRecipeData(item);

        if (result != null) {
          return result;
        }
      }

      return null;
    }

    if (value is Map) {
      final map = Map<String, dynamic>.from(value);

      if (_isRecipeType(map['@type'])) {
        return map;
      }

      final graph = map['@graph'];

      if (graph != null) {
        final result = _findRecipeData(graph);

        if (result != null) {
          return result;
        }
      }

      for (final child in map.values) {
        final result = _findRecipeData(child);

        if (result != null) {
          return result;
        }
      }
    }

    return null;
  }

  static bool _isRecipeType(dynamic type) {
    if (type is String) {
      final normalizedType = type
          .toLowerCase()
          .replaceAll('schema:', '')
          .trim();

      return normalizedType == 'recipe' ||
          normalizedType.endsWith('/recipe') ||
          normalizedType.contains('recipe');
    }

    if (type is List) {
      return type.any(_isRecipeType);
    }

    return false;
  }

  static Recipe _buildRecipeFromJsonLd(Map<String, dynamic> data) {
    final name = _readString(data['name']) ?? 'Nouvelle recette';
    final ingredientTexts = _readStringList(data['recipeIngredient']);
    final ingredients = ingredientTexts
        .map(RecipeTextParser.parseIngredientLine)
        .where((ingredient) => ingredient.name.trim().isNotEmpty)
        .toList();
    final steps = _readInstructions(data['recipeInstructions']);

    return Recipe(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      ingredients: ingredients.isEmpty
          ? [const Ingredient(name: 'À compléter')]
          : ingredients,
      steps: steps.trim().isEmpty ? 'À compléter.' : steps.trim(),
      prepTimeMinutes: _parseIsoDurationToMinutes(data['prepTime']),
      cookTimeMinutes: _parseIsoDurationToMinutes(data['cookTime']),
    );
  }

  static String? _readString(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is String) {
      final trimmed = value.trim();

      if (trimmed.isEmpty) {
        return null;
      }

      return trimmed;
    }

    return value.toString().trim();
  }

  static List<String> _readStringList(dynamic value) {
    if (value == null) {
      return [];
    }

    if (value is String) {
      return value
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
    }

    if (value is List) {
      return value
          .map(_readString)
          .whereType<String>()
          .where((line) => line.trim().isNotEmpty)
          .toList();
    }

    return [];
  }

  static String _readInstructions(dynamic value) {
    final lines = _extractInstructionLines(value);

    return lines.join('\n');
  }

  static List<String> _extractInstructionLines(dynamic value) {
    if (value == null) {
      return [];
    }

    if (value is String) {
      return value
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
    }

    if (value is List) {
      final lines = <String>[];

      for (final item in value) {
        lines.addAll(_extractInstructionLines(item));
      }

      return lines;
    }

    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      final text = _readString(map['text']);

      if (text != null) {
        return [text];
      }

      final name = _readString(map['name']);

      if (name != null) {
        return [name];
      }

      final itemListElement = map['itemListElement'];

      if (itemListElement != null) {
        return _extractInstructionLines(itemListElement);
      }
    }

    return [];
  }

  static int? _parseIsoDurationToMinutes(dynamic value) {
    final rawValue = _readString(value);

    if (rawValue == null) {
      return null;
    }

    final match = RegExp(
      r'^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$',
      caseSensitive: false,
    ).firstMatch(rawValue);

    if (match == null) {
      return null;
    }

    final days = int.tryParse(match.group(1) ?? '') ?? 0;
    final hours = int.tryParse(match.group(2) ?? '') ?? 0;
    final minutes = int.tryParse(match.group(3) ?? '') ?? 0;
    final seconds = int.tryParse(match.group(4) ?? '') ?? 0;
    final totalMinutes = (days * 24 * 60) + (hours * 60) + minutes;

    if (seconds > 0 && totalMinutes == 0) {
      return 1;
    }

    if (totalMinutes == 0) {
      return null;
    }

    return totalMinutes;
  }
}

class RecipeUrlImportException implements Exception {
  const RecipeUrlImportException(this.message);

  final String message;

  @override
  String toString() {
    return message;
  }
}
