import '../data/seasonal_ingredients.dart';
import '../models/recipe.dart';

class RecipeSeasonality {
  const RecipeSeasonality({
    required this.totalProduceIngredients,
    required this.seasonalProduceIngredients,
    required this.seasonalMatches,
  });

  final int totalProduceIngredients;
  final int seasonalProduceIngredients;
  final List<String> seasonalMatches;

  bool get hasProduceIngredients => totalProduceIngredients > 0;

  bool get hasSeasonalProduce => seasonalProduceIngredients > 0;

  bool get isFullySeasonal {
    return hasProduceIngredients &&
        seasonalProduceIngredients == totalProduceIngredients;
  }

  int get score {
    if (totalProduceIngredients == 0) {
      return 0;
    }

    return ((seasonalProduceIngredients / totalProduceIngredients) * 100)
        .round();
  }

  String get summaryText {
    if (!hasProduceIngredients) {
      return 'Aucun fruit ou légume détecté';
    }

    return '$seasonalProduceIngredients/$totalProduceIngredients fruit(s) ou légume(s) de saison';
  }
}

class SeasonalityService {
  static RecipeSeasonality analyzeRecipe(Recipe recipe) {
    final currentSeasonalIngredients = getCurrentSeasonalIngredients();
    final seasonalMatches = <String>{};

    int totalProduceIngredients = 0;
    int seasonalProduceIngredients = 0;

    for (final ingredient in recipe.ingredients) {
      final isProduce = ingredientNameMatchesKnownProduce(ingredient.name);

      if (!isProduce) {
        continue;
      }

      totalProduceIngredients++;

      final matchingSeasonalIngredients = currentSeasonalIngredients.where((
        seasonalIngredient,
      ) {
        return ingredientNameMatchesSeasonalItem(
          ingredientName: ingredient.name,
          seasonalItem: seasonalIngredient,
        );
      }).toList();

      if (matchingSeasonalIngredients.isNotEmpty) {
        seasonalProduceIngredients++;
        seasonalMatches.addAll(matchingSeasonalIngredients);
      }
    }

    final sortedMatches = seasonalMatches.toList()..sort();

    return RecipeSeasonality(
      totalProduceIngredients: totalProduceIngredients,
      seasonalProduceIngredients: seasonalProduceIngredients,
      seasonalMatches: sortedMatches,
    );
  }
}
