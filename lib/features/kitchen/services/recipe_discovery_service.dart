import 'dart:math';

import '../models/recipe.dart';
import 'recipe_url_importer.dart';

class RecipeDiscoveryService {
  static const List<String> _popularMarmitonDishUrls = [
    'https://www.marmiton.org/recettes/recette_quiche-lorraine_30283.aspx',
    'https://www.marmiton.org/recettes/recette_boeuf-bourguignon_18889.aspx',
    'https://www.marmiton.org/recettes/recette_blanquette-de-veau-facile_19219.aspx',
    'https://www.marmiton.org/recettes/recette_ratatouille_23223.aspx',
    'https://www.marmiton.org/recettes/recette_la-vraie-tartiflette_17634.aspx',
    'https://www.marmiton.org/recettes/recette_lasagnes-a-la-bolognaise_18215.aspx',
    'https://www.marmiton.org/recettes/recette_gratin-dauphinois_13809.aspx',
    'https://www.marmiton.org/recettes/recette_gratin-dauphinois-recette-originale_22307.aspx',
    'https://www.marmiton.org/recettes/recette_cake-sale-au-jambon-et-aux-olives_18876.aspx',
    'https://www.marmiton.org/recettes/recette_hachis-parmentier_17639.aspx',
    'https://www.marmiton.org/recettes/recette_pot-au-feu-a-l-autocuiseur_20533.aspx',
    'https://www.marmiton.org/recettes/recette_couscous-poulet-et-merguez-facile_17751.aspx',
    'https://www.marmiton.org/recettes/recette_chili-con-carne-facile_15415.aspx',
    'https://www.marmiton.org/recettes/recette_poulet-curry-et-oignons-facile_13026.aspx',
    'https://www.marmiton.org/recettes/recette_poulet-basquaise_16969.aspx',
    'https://www.marmiton.org/recettes/recette_poulet-roti-et-ses-pommes-de-terre_43958.aspx',
    'https://www.marmiton.org/recettes/recette_filet-mignon-a-la-moutarde-facile_37368.aspx',
    'https://www.marmiton.org/recettes/recette_rougail-saucisse_22851.aspx',
    'https://www.marmiton.org/recettes/recette_spaghetti-a-la-carbonara_12249.aspx',
    'https://www.marmiton.org/recettes/recette_spaghetti-bolognaise_19840.aspx',
    'https://www.marmiton.org/recettes/recette_risotto-aux-champignons-recette-italienne-du-risotto-alla-fungaiola_29870.aspx',
    'https://www.marmiton.org/recettes/recette_tomates-farcies-au-chevre-chaud_23616.aspx',
    'https://www.marmiton.org/recettes/recette_gratin-de-courgettes-rapide_17071.aspx',
    'https://www.marmiton.org/recettes/recette_soupe-au-potiron_18643.aspx',
    'https://www.marmiton.org/recettes/recette_veloute-de-champignons_26749.aspx',
    'https://www.marmiton.org/recettes/recette_saucisses-aux-lentilles_22979.aspx',
    'https://www.marmiton.org/recettes/recette_croque-monsieur-d-aubergines_32571.aspx',
    'https://www.marmiton.org/recettes/recette_endive-jambon_19848.aspx',
  ];

  static Future<Recipe> importPopularMarmitonRecipe({
    required Iterable<Recipe> existingRecipes,
  }) async {
    final excludedUrls = existingRecipes
        .map((recipe) => recipe.sourceUrl)
        .whereType<String>()
        .map(_normalizeRecipeUrl)
        .toSet();

    final candidates = _popularMarmitonDishUrls
        .where((url) => !excludedUrls.contains(_normalizeRecipeUrl(url)))
        .toList();

    if (candidates.isEmpty) {
      throw const RecipeDiscoveryException(
        'Tous les plats proposés sont déjà présents.',
      );
    }

    _shuffleBySmallWindows(candidates);

    for (final url in candidates) {
      try {
        final recipe = await RecipeUrlImporter.importFromUrl(url);

        return recipe.copyWith(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          reviewStatus: 'À vérifier',
          tags: _inferTags(url),
          emoji: _inferEmoji(url),
        );
      } catch (_) {
        // Si Marmiton bloque temporairement une page ou si une recette change de
        // structure, on passe simplement à la candidate suivante.
      }
    }

    throw const RecipeDiscoveryException(
      'Aucun plat Marmiton proposé n’a pu être importé.',
    );
  }

  static void _shuffleBySmallWindows(List<String> urls) {
    const windowSize = 5;
    final random = Random();

    for (var start = 0; start < urls.length; start += windowSize) {
      final end = min(start + windowSize, urls.length);
      final window = urls.sublist(start, end)..shuffle(random);

      urls.replaceRange(start, end, window);
    }
  }

  static String _normalizeRecipeUrl(String url) {
    final uri = Uri.tryParse(url.trim());

    if (uri == null) {
      return url.trim();
    }

    return Uri(scheme: uri.scheme, host: uri.host, path: uri.path).toString();
  }

  static List<String> _inferTags(String url) {
    final value = url.toLowerCase();
    final tags = <String>[];

    if (RegExp('soupe|veloute|velouté').hasMatch(value)) {
      tags.add('Entrée');
    } else if (RegExp('ratatouille|gratin-dauphinois').hasMatch(value)) {
      tags.add('Accompagnement');
    } else {
      tags.add('Plat principal');
    }

    if (RegExp(
      'quiche|tartiflette|lasagne|gratin|cake|hachis|roti|rôti|tomates|'
      'croque|endive',
    ).hasMatch(value)) {
      tags.add('Four');
    } else {
      tags.add('Plaque de cuisson');
    }

    return tags;
  }

  static String _inferEmoji(String url) {
    final value = url.toLowerCase();

    if (value.contains('tarte') || value.contains('quiche')) {
      return '🥧';
    }
    if (value.contains('poulet')) {
      return '🍗';
    }
    if (value.contains('soupe') || value.contains('veloute')) {
      return '🥣';
    }
    if (value.contains('pate') ||
        value.contains('spaghetti') ||
        value.contains('risotto') ||
        value.contains('lasagne')) {
      return '🍝';
    }

    return '🍽️';
  }
}

class RecipeDiscoveryException implements Exception {
  const RecipeDiscoveryException(this.message);

  final String message;

  @override
  String toString() {
    return message;
  }
}
