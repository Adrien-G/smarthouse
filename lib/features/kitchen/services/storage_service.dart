import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/pantry_ingredients.dart';
import '../models/meal_history_entry.dart';
import '../models/recipe.dart';

class AppData {
  const AppData({
    required this.recipes,
    required this.weeklyPlanning,
    required this.checkedShoppingItems,
    required this.pantryIngredientNames,
    required this.mealHistoryEntries,
  });

  final List<Recipe> recipes;
  final Map<String, String> weeklyPlanning;
  final Set<String> checkedShoppingItems;
  final List<String> pantryIngredientNames;
  final List<MealHistoryEntry> mealHistoryEntries;
}

class StorageService {
  static const recipesStorageKey = 'recipes';
  static const planningStorageKey = 'weeklyPlanning';
  static const checkedItemsStorageKey = 'checkedShoppingItems';
  static const pantryIngredientsStorageKey = 'pantryIngredientNames';
  static const mealHistoryStorageKey = 'mealHistoryEntries';

  Future<AppData> loadData() async {
    final prefs = await SharedPreferences.getInstance();

    final savedRecipes = prefs.getString(recipesStorageKey);
    final savedPlanning = prefs.getString(planningStorageKey);
    final savedCheckedItems = prefs.getStringList(checkedItemsStorageKey);
    final savedPantryIngredients = prefs.getStringList(
      pantryIngredientsStorageKey,
    );
    final savedMealHistory = prefs.getString(mealHistoryStorageKey);

    final List<Recipe> loadedRecipes = [];
    final Map<String, String> loadedPlanning = {};
    final Set<String> loadedCheckedItems = {};
    final loadedPantryIngredients = savedPantryIngredients == null
        ? normalizePantryIngredientNames(defaultPantryIngredientNames)
        : normalizePantryIngredientNames(savedPantryIngredients);
    final List<MealHistoryEntry> loadedMealHistoryEntries = [];

    if (savedRecipes != null) {
      final decodedRecipes = jsonDecode(savedRecipes) as List;

      for (final item in decodedRecipes) {
        loadedRecipes.add(Recipe.fromJson(item as Map<String, dynamic>));
      }
    }

    if (savedPlanning != null) {
      final decodedPlanning = jsonDecode(savedPlanning) as Map<String, dynamic>;

      for (final entry in decodedPlanning.entries) {
        loadedPlanning[entry.key] = entry.value as String;
      }
    }

    if (savedCheckedItems != null) {
      loadedCheckedItems.addAll(savedCheckedItems);
    }

    if (savedMealHistory != null) {
      final decodedMealHistory = jsonDecode(savedMealHistory) as List;

      for (final item in decodedMealHistory) {
        loadedMealHistoryEntries.add(
          MealHistoryEntry.fromJson(Map<String, dynamic>.from(item as Map)),
        );
      }
    }

    return AppData(
      recipes: loadedRecipes,
      weeklyPlanning: loadedPlanning,
      checkedShoppingItems: loadedCheckedItems,
      pantryIngredientNames: loadedPantryIngredients,
      mealHistoryEntries: loadedMealHistoryEntries,
    );
  }

  Future<void> saveData({
    required List<Recipe> recipes,
    required Map<String, String> weeklyPlanning,
    required Set<String> checkedShoppingItems,
    required List<String> pantryIngredientNames,
    required List<MealHistoryEntry> mealHistoryEntries,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final recipesJson = jsonEncode(
      recipes.map((recipe) => recipe.toJson()).toList(),
    );

    final planningJson = jsonEncode(weeklyPlanning);
    final mealHistoryJson = jsonEncode(
      mealHistoryEntries.map((entry) => entry.toJson()).toList(),
    );

    await prefs.setString(recipesStorageKey, recipesJson);
    await prefs.setString(planningStorageKey, planningJson);
    await prefs.setStringList(
      checkedItemsStorageKey,
      checkedShoppingItems.toList(),
    );
    await prefs.setStringList(
      pantryIngredientsStorageKey,
      normalizePantryIngredientNames(pantryIngredientNames),
    );
    await prefs.setString(mealHistoryStorageKey, mealHistoryJson);
  }
}
