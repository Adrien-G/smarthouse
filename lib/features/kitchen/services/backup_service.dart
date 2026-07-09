import 'dart:convert';

import '../models/meal_history_entry.dart';
import '../models/recipe.dart';
import 'storage_service.dart';

class BackupService {
  static const String backupFormat = 'cuisine_app_backup';
  static const int backupVersion = 1;

  static String createBackupJson(AppData appData) {
    final backup = {
      'format': backupFormat,
      'version': backupVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'recipes': appData.recipes.map((recipe) => recipe.toJson()).toList(),
      'weeklyPlanning': appData.weeklyPlanning,
      'checkedShoppingItems': appData.checkedShoppingItems.toList(),
      'pantryIngredientNames': appData.pantryIngredientNames,
      'mealHistoryEntries': appData.mealHistoryEntries
          .map((entry) => entry.toJson())
          .toList(),
    };

    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(backup);
  }

  static AppData parseBackupJson(String rawJson) {
    final decoded = jsonDecode(rawJson);

    if (decoded is! Map) {
      throw const BackupException(
        'Le fichier ne contient pas une sauvegarde valide.',
      );
    }

    final json = Map<String, dynamic>.from(decoded);

    if (json['format'] != backupFormat) {
      throw const BackupException(
        'Ce fichier ne semble pas être une sauvegarde de cette application.',
      );
    }

    final rawRecipes = json['recipes'];

    if (rawRecipes is! List) {
      throw const BackupException(
        'La sauvegarde ne contient pas de liste de recettes valide.',
      );
    }

    final recipes = rawRecipes.map((item) {
      return Recipe.fromJson(Map<String, dynamic>.from(item as Map));
    }).toList();

    final weeklyPlanning = <String, String>{};
    final rawPlanning = json['weeklyPlanning'];

    if (rawPlanning is Map) {
      for (final entry in rawPlanning.entries) {
        weeklyPlanning[entry.key.toString()] = entry.value.toString();
      }
    }

    final checkedShoppingItems = <String>{};
    final rawCheckedItems = json['checkedShoppingItems'];

    if (rawCheckedItems is List) {
      checkedShoppingItems.addAll(
        rawCheckedItems.map((item) => item.toString()),
      );
    }

    final pantryIngredientNames = <String>[];
    final rawPantryIngredients = json['pantryIngredientNames'];

    if (rawPantryIngredients is List) {
      pantryIngredientNames.addAll(
        rawPantryIngredients.map((item) => item.toString()),
      );
    }

    final mealHistoryEntries = <MealHistoryEntry>[];
    final rawMealHistory = json['mealHistoryEntries'];

    if (rawMealHistory is List) {
      for (final item in rawMealHistory) {
        mealHistoryEntries.add(
          MealHistoryEntry.fromJson(Map<String, dynamic>.from(item as Map)),
        );
      }
    }

    return AppData(
      recipes: recipes,
      weeklyPlanning: weeklyPlanning,
      checkedShoppingItems: checkedShoppingItems,
      pantryIngredientNames: pantryIngredientNames,
      mealHistoryEntries: mealHistoryEntries,
    );
  }

  static String buildBackupFileName() {
    final now = DateTime.now();

    String twoDigits(int value) {
      return value.toString().padLeft(2, '0');
    }

    final date =
        '${now.year}-${twoDigits(now.month)}-${twoDigits(now.day)}_'
        '${twoDigits(now.hour)}-${twoDigits(now.minute)}';

    return 'cuisine_sauvegarde_$date.json';
  }
}

class BackupException implements Exception {
  const BackupException(this.message);

  final String message;

  @override
  String toString() {
    return message;
  }
}
