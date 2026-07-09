import 'dart:math';

import '../data/meal_slots.dart';
import '../data/pantry_ingredients.dart';
import '../data/planning_entries.dart';
import '../models/ingredient.dart';
import '../models/meal_history_entry.dart';
import '../models/recipe.dart';
import '../services/recipe_text_parser.dart';
import '../services/seasonality_service.dart';
import '../services/storage_service.dart';

enum SelectAccompanimentResult { added, missingMainRecipe, fullDish }

enum MergePlanningMode { fillEmptySlots, replace }

class FillPlanningResult {
  const FillPlanningResult({
    required this.addedMealsCount,
    required this.hasRecipes,
  });

  final int addedMealsCount;
  final bool hasRecipes;

  bool get isPlanningAlreadyFull => hasRecipes && addedMealsCount == 0;
}

class IngredientCategoryMaintenanceResult {
  const IngredientCategoryMaintenanceResult({
    required this.updatedIngredientsCount,
    required this.updatedRecipesCount,
  });

  final int updatedIngredientsCount;
  final int updatedRecipesCount;

  bool get hasUpdates => updatedIngredientsCount > 0;
}

class RecordPlannedMealsResult {
  const RecordPlannedMealsResult({
    required this.addedEntriesCount,
    required this.hasPlannedRecipes,
  });

  final int addedEntriesCount;
  final bool hasPlannedRecipes;

  bool get hasNewEntries => addedEntriesCount > 0;
}

class RecordCookedRecipeResult {
  const RecordCookedRecipeResult({
    required this.wasAdded,
    required this.wasPlanningMealCleared,
  });

  final bool wasAdded;
  final bool wasPlanningMealCleared;
}

class MergeBackupResult {
  const MergeBackupResult({
    required this.addedRecipesCount,
    required this.updatedRecipesCount,
    required this.addedPlanningEntriesCount,
    required this.addedPantryIngredientsCount,
    required this.addedMealHistoryEntriesCount,
  });

  final int addedRecipesCount;
  final int updatedRecipesCount;
  final int addedPlanningEntriesCount;
  final int addedPantryIngredientsCount;
  final int addedMealHistoryEntriesCount;

  int get totalChanges {
    return addedRecipesCount +
        updatedRecipesCount +
        addedPlanningEntriesCount +
        addedPantryIngredientsCount +
        addedMealHistoryEntriesCount;
  }

  bool get hasChanges => totalChanges > 0;
}

class CuisineController {
  CuisineController({StorageService? storageService})
    : _storageService = storageService ?? StorageService();

  final StorageService _storageService;

  bool isLoading = true;

  final List<Recipe> recipes = [];
  final Map<String, String> weeklyPlanning = {};
  final Set<String> checkedShoppingItems = {};
  final List<String> pantryIngredientNames = [];
  final List<MealHistoryEntry> mealHistoryEntries = [];

  AppData get appData {
    return AppData(
      recipes: List<Recipe>.from(recipes),
      weeklyPlanning: Map<String, String>.from(weeklyPlanning),
      checkedShoppingItems: Set<String>.from(checkedShoppingItems),
      pantryIngredientNames: List<String>.from(pantryIngredientNames),
      mealHistoryEntries: List<MealHistoryEntry>.from(mealHistoryEntries),
    );
  }

  Future<void> loadData() async {
    final appData = await _storageService.loadData();

    final migratedPlanning = migrateLegacyPlanning(appData.weeklyPlanning);
    final hasLegacyPlanning = containsLegacyPlanningKeys(
      appData.weeklyPlanning,
    );

    recipes
      ..clear()
      ..addAll(appData.recipes);

    weeklyPlanning
      ..clear()
      ..addAll(migratedPlanning);

    checkedShoppingItems
      ..clear()
      ..addAll(appData.checkedShoppingItems);

    pantryIngredientNames
      ..clear()
      ..addAll(appData.pantryIngredientNames);

    mealHistoryEntries
      ..clear()
      ..addAll(appData.mealHistoryEntries);

    isLoading = false;

    if (hasLegacyPlanning) {
      await saveData();
    }
  }

  Future<void> saveData() {
    return _storageService.saveData(
      recipes: recipes,
      weeklyPlanning: weeklyPlanning,
      checkedShoppingItems: checkedShoppingItems,
      pantryIngredientNames: pantryIngredientNames,
      mealHistoryEntries: mealHistoryEntries,
    );
  }

  Future<void> restoreDataFromBackup(AppData importedData) async {
    recipes
      ..clear()
      ..addAll(importedData.recipes);

    weeklyPlanning
      ..clear()
      ..addAll(importedData.weeklyPlanning);

    checkedShoppingItems
      ..clear()
      ..addAll(importedData.checkedShoppingItems);

    pantryIngredientNames
      ..clear()
      ..addAll(
        importedData.pantryIngredientNames.isEmpty
            ? normalizePantryIngredientNames(defaultPantryIngredientNames)
            : importedData.pantryIngredientNames,
      );

    mealHistoryEntries
      ..clear()
      ..addAll(importedData.mealHistoryEntries);

    await saveData();
  }

  Future<MergeBackupResult> mergeDataFromBackup(
    AppData importedData, {
    MergePlanningMode planningMode = MergePlanningMode.fillEmptySlots,
  }) async {
    var addedRecipesCount = 0;
    var updatedRecipesCount = 0;
    var addedPlanningEntriesCount = 0;
    var addedPantryIngredientsCount = 0;
    var addedMealHistoryEntriesCount = 0;

    final recipesById = {for (final recipe in recipes) recipe.id: recipe};

    for (final importedRecipe in importedData.recipes) {
      final existingRecipe = recipesById[importedRecipe.id];

      if (existingRecipe == null) {
        recipes.add(importedRecipe);
        recipesById[importedRecipe.id] = importedRecipe;
        addedRecipesCount++;
        continue;
      }

      if (recipeContentSignature(existingRecipe) !=
          recipeContentSignature(importedRecipe)) {
        final index = recipes.indexWhere((recipe) {
          return recipe.id == importedRecipe.id;
        });

        if (index != -1) {
          recipes[index] = importedRecipe;
          recipesById[importedRecipe.id] = importedRecipe;
          updatedRecipesCount++;
        }
      }
    }

    final migratedImportedPlanning = migrateLegacyPlanning(
      importedData.weeklyPlanning,
    );

    switch (planningMode) {
      case MergePlanningMode.fillEmptySlots:
        for (final entry in migratedImportedPlanning.entries) {
          if (!weeklyPlanning.containsKey(entry.key)) {
            weeklyPlanning[entry.key] = entry.value;
            addedPlanningEntriesCount++;
          }
        }
      case MergePlanningMode.replace:
        if (!mapEquals(weeklyPlanning, migratedImportedPlanning)) {
          weeklyPlanning
            ..clear()
            ..addAll(migratedImportedPlanning);
          addedPlanningEntriesCount = migratedImportedPlanning.length;
        }
    }

    final mergedPantryIngredientNames = [
      ...pantryIngredientNames,
      ...importedData.pantryIngredientNames,
    ];
    final previousPantryIngredientCount = pantryIngredientNames.length;
    pantryIngredientNames
      ..clear()
      ..addAll(normalizePantryIngredientNames(mergedPantryIngredientNames));
    addedPantryIngredientsCount =
        pantryIngredientNames.length - previousPantryIngredientCount;

    final mealHistoryIds = mealHistoryEntries.map((entry) => entry.id).toSet();

    for (final importedEntry in importedData.mealHistoryEntries) {
      if (mealHistoryIds.add(importedEntry.id)) {
        mealHistoryEntries.add(importedEntry);
        addedMealHistoryEntriesCount++;
      }
    }

    sortMealHistoryEntries();

    if (addedRecipesCount > 0 ||
        updatedRecipesCount > 0 ||
        addedPlanningEntriesCount > 0 ||
        addedPantryIngredientsCount > 0 ||
        addedMealHistoryEntriesCount > 0) {
      checkedShoppingItems.clear();
      await saveData();
    }

    return MergeBackupResult(
      addedRecipesCount: addedRecipesCount,
      updatedRecipesCount: updatedRecipesCount,
      addedPlanningEntriesCount: addedPlanningEntriesCount,
      addedPantryIngredientsCount: addedPantryIngredientsCount,
      addedMealHistoryEntriesCount: addedMealHistoryEntriesCount,
    );
  }

  String recipeContentSignature(Recipe recipe) {
    return [
      recipe.name,
      recipe.steps,
      recipe.tags.join('|'),
      recipe.prepTimeMinutes?.toString() ?? '',
      recipe.cookTimeMinutes?.toString() ?? '',
      recipe.rating?.toString() ?? '',
      recipe.reviewStatus,
      recipe.emoji,
      for (final ingredient in recipe.ingredients)
        [
          ingredient.name,
          ingredient.quantity?.toString() ?? '',
          ingredient.unit,
          ingredient.category,
          ingredient.includeInShoppingList.toString(),
        ].join('~'),
    ].join('||');
  }

  bool mapEquals(Map<String, String> first, Map<String, String> second) {
    if (first.length != second.length) {
      return false;
    }

    for (final entry in first.entries) {
      if (second[entry.key] != entry.value) {
        return false;
      }
    }

    return true;
  }

  Future<void> addRecipe(Recipe newRecipe) async {
    recipes.add(newRecipe);
    await saveData();
  }

  Future<void> updateRecipe(Recipe updatedRecipe) async {
    final index = recipes.indexWhere((recipe) => recipe.id == updatedRecipe.id);

    if (index != -1) {
      recipes[index] = updatedRecipe;
    }

    checkedShoppingItems.clear();

    await saveData();
  }

  Future<void> updatePantryIngredientNames(
    Iterable<String> updatedIngredientNames,
  ) async {
    pantryIngredientNames
      ..clear()
      ..addAll(normalizePantryIngredientNames(updatedIngredientNames));

    checkedShoppingItems.clear();

    await saveData();
  }

  int countSafeIngredientCategoryUpdates() {
    var count = 0;

    for (final recipe in recipes) {
      for (final ingredient in recipe.ingredients) {
        if (_shouldUpdateIngredientCategorySafely(ingredient)) {
          count++;
        }
      }
    }

    return count;
  }

  Future<IngredientCategoryMaintenanceResult>
  updateSafeIngredientCategories() async {
    var updatedIngredientsCount = 0;
    var updatedRecipesCount = 0;

    for (var index = 0; index < recipes.length; index++) {
      final recipe = recipes[index];
      var recipeWasUpdated = false;

      final updatedIngredients = recipe.ingredients.map((ingredient) {
        if (!_shouldUpdateIngredientCategorySafely(ingredient)) {
          return ingredient;
        }

        recipeWasUpdated = true;
        updatedIngredientsCount++;

        return ingredient.copyWith(
          category: RecipeTextParser.guessCategory(ingredient.name),
        );
      }).toList();

      if (recipeWasUpdated) {
        updatedRecipesCount++;
        recipes[index] = recipe.copyWith(ingredients: updatedIngredients);
      }
    }

    if (updatedIngredientsCount > 0) {
      checkedShoppingItems.clear();
      await saveData();
    }

    return IngredientCategoryMaintenanceResult(
      updatedIngredientsCount: updatedIngredientsCount,
      updatedRecipesCount: updatedRecipesCount,
    );
  }

  bool _shouldUpdateIngredientCategorySafely(Ingredient ingredient) {
    final currentCategory = ingredient.category.trim();
    final suggestedCategory = RecipeTextParser.guessCategory(ingredient.name);

    if (currentCategory == suggestedCategory ||
        suggestedCategory != 'Épicerie') {
      return false;
    }

    return _isKnownPantryMaintenanceIngredient(ingredient.name);
  }

  bool _isKnownPantryMaintenanceIngredient(String ingredientName) {
    final normalizedName = _normalizeIngredientForMaintenance(ingredientName);

    return RegExp(r'(^| )(lait|oeuf)( |s|x|$)').hasMatch(normalizedName);
  }

  String _normalizeIngredientForMaintenance(String value) {
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
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<void> deleteRecipe(Recipe recipeToDelete) async {
    recipes.removeWhere((recipe) => recipe.id == recipeToDelete.id);

    weeklyPlanning.removeWhere((slotId, planningValue) {
      return getRecipeIdsFromPlanningValue(
        planningValue,
      ).contains(recipeToDelete.id);
    });

    checkedShoppingItems.clear();

    await saveData();
  }

  Future<String> setSpecialMealForSlot(String slotId, String label) async {
    final specialMealLabel = label.trim().isEmpty
        ? defaultSpecialMealLabel
        : label.trim();

    weeklyPlanning[slotId] = buildSpecialMealValue(specialMealLabel);
    checkedShoppingItems.clear();

    await saveData();

    return specialMealLabel;
  }

  Recipe? getRecipeById(String recipeId) {
    for (final recipe in recipes) {
      if (recipe.id == recipeId) {
        return recipe;
      }
    }

    return null;
  }

  Future<SelectAccompanimentResult> selectAccompanimentForSlot(
    String slotId,
    Recipe accompanimentRecipe,
  ) async {
    final currentValue = weeklyPlanning[slotId];
    final mainRecipeId = getMainRecipeIdFromPlanningValue(currentValue);

    if (mainRecipeId == null) {
      return SelectAccompanimentResult.missingMainRecipe;
    }

    final mainRecipe = getRecipeById(mainRecipeId);

    if (mainRecipe == null) {
      return SelectAccompanimentResult.missingMainRecipe;
    }

    if (mainRecipe.tags.contains('Plat complet')) {
      return SelectAccompanimentResult.fullDish;
    }

    weeklyPlanning[slotId] = buildRecipePlanningValue(
      recipeId: mainRecipeId,
      accompanimentRecipeId: accompanimentRecipe.id,
    );
    checkedShoppingItems.clear();

    await saveData();

    return SelectAccompanimentResult.added;
  }

  Future<void> removeAccompanimentFromSlot(String slotId) async {
    final currentValue = weeklyPlanning[slotId];

    if (currentValue == null) {
      return;
    }

    weeklyPlanning[slotId] = removeAccompanimentFromPlanningValue(currentValue);
    checkedShoppingItems.clear();

    await saveData();
  }

  Future<void> selectRecipeForSlot(String slotId, Recipe recipe) async {
    weeklyPlanning[slotId] = buildRecipePlanningValue(recipeId: recipe.id);
    checkedShoppingItems.clear();

    await saveData();
  }

  Future<void> removeRecipeFromSlot(String slotId) async {
    weeklyPlanning.remove(slotId);
    checkedShoppingItems.clear();

    await saveData();
  }

  Future<void> resetWeek() async {
    weeklyPlanning.clear();
    checkedShoppingItems.clear();

    await saveData();
  }

  Future<RecordPlannedMealsResult> recordPlannedMealsAsCooked() async {
    final newEntries = buildMealHistoryEntriesFromPlanning();

    if (newEntries.isEmpty) {
      return const RecordPlannedMealsResult(
        addedEntriesCount: 0,
        hasPlannedRecipes: false,
      );
    }

    final existingEntryIds = mealHistoryEntries
        .map((entry) => entry.id)
        .toSet();
    final entriesToAdd = newEntries.where((entry) {
      return !existingEntryIds.contains(entry.id);
    }).toList();

    if (entriesToAdd.isEmpty) {
      return const RecordPlannedMealsResult(
        addedEntriesCount: 0,
        hasPlannedRecipes: true,
      );
    }

    mealHistoryEntries.addAll(entriesToAdd);
    sortMealHistoryEntries();

    await saveData();

    return RecordPlannedMealsResult(
      addedEntriesCount: entriesToAdd.length,
      hasPlannedRecipes: true,
    );
  }

  Future<RecordCookedRecipeResult> recordCookedRecipe({
    required Recipe recipe,
    required DateTime cookedAt,
    required String mealLabel,
    String? sourcePlanningSlotId,
  }) async {
    final entry = MealHistoryEntry(
      id: buildMealHistoryEntryId(
        cookedAt: cookedAt,
        slotId: mealLabel,
        recipeId: recipe.id,
      ),
      recipeId: recipe.id,
      recipeName: recipe.name,
      recipeEmoji: recipe.emoji,
      slotId: mealLabel,
      slotLabel: mealLabel,
      cookedAt: cookedAt,
    );

    final wasAdded = !mealHistoryEntries.any((item) => item.id == entry.id);

    if (wasAdded) {
      mealHistoryEntries.add(entry);
      sortMealHistoryEntries();
    }

    final wasPlanningMealCleared = clearPlanningSlotIfMatchingCookedMeal(
      sourcePlanningSlotId: sourcePlanningSlotId,
      recipe: recipe,
      cookedAt: cookedAt,
      mealLabel: mealLabel,
    );

    if (wasAdded || wasPlanningMealCleared) {
      await saveData();
    }

    return RecordCookedRecipeResult(
      wasAdded: wasAdded,
      wasPlanningMealCleared: wasPlanningMealCleared,
    );
  }

  bool clearPlanningSlotIfMatchingCookedMeal({
    required String? sourcePlanningSlotId,
    required Recipe recipe,
    required DateTime cookedAt,
    required String mealLabel,
  }) {
    if (sourcePlanningSlotId == null) {
      return false;
    }

    MealSlot? slot;

    for (final item in mealSlots) {
      if (item.id == sourcePlanningSlotId) {
        slot = item;
        break;
      }
    }

    if (slot == null || slot.meal != mealLabel) {
      return false;
    }

    final expectedDate = getCookedAtForSlot(slot, getCurrentWeekStart());
    final isExpectedDate =
        cookedAt.year == expectedDate.year &&
        cookedAt.month == expectedDate.month &&
        cookedAt.day == expectedDate.day;

    if (!isExpectedDate) {
      return false;
    }

    final currentPlanningValue = weeklyPlanning[sourcePlanningSlotId];
    final plannedRecipeIds = getRecipeIdsFromPlanningValue(
      currentPlanningValue,
    );

    if (!plannedRecipeIds.contains(recipe.id)) {
      return false;
    }

    weeklyPlanning.remove(sourcePlanningSlotId);
    checkedShoppingItems.clear();

    return true;
  }

  List<MealHistoryEntry> buildMealHistoryEntriesFromPlanning() {
    final weekStart = getCurrentWeekStart();
    final entries = <MealHistoryEntry>[];

    for (final slot in mealSlots) {
      final planningValue = weeklyPlanning[slot.id];

      if (planningValue == null) {
        continue;
      }

      final recipeIds = getRecipeIdsFromPlanningValue(planningValue);

      if (recipeIds.isEmpty) {
        continue;
      }

      final cookedAt = getCookedAtForSlot(slot, weekStart);

      for (final recipeId in recipeIds) {
        final recipe = getRecipeById(recipeId);

        if (recipe == null) {
          continue;
        }

        entries.add(
          MealHistoryEntry(
            id: buildMealHistoryEntryId(
              cookedAt: cookedAt,
              slotId: slot.id,
              recipeId: recipe.id,
            ),
            recipeId: recipe.id,
            recipeName: recipe.name,
            recipeEmoji: recipe.emoji,
            slotId: slot.id,
            slotLabel: slot.label,
            cookedAt: cookedAt,
          ),
        );
      }
    }

    return entries;
  }

  DateTime getCurrentWeekStart() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return today.subtract(Duration(days: today.weekday - DateTime.monday));
  }

  DateTime getCookedAtForSlot(MealSlot slot, DateTime weekStart) {
    final dayIndex = mealSlotDays.indexOf(slot.day);
    final safeDayIndex = dayIndex == -1 ? 0 : dayIndex;
    final hour = slot.meal == 'Midi' ? 12 : 19;

    return weekStart.add(Duration(days: safeDayIndex, hours: hour));
  }

  String buildMealHistoryEntryId({
    required DateTime cookedAt,
    required String slotId,
    required String recipeId,
  }) {
    final date = cookedAt.toIso8601String().split('T').first;

    return '$date|$slotId|$recipeId';
  }

  void sortMealHistoryEntries() {
    mealHistoryEntries.sort((a, b) {
      return b.cookedAt.compareTo(a.cookedAt);
    });
  }

  Future<FillPlanningResult> fillEmptySlotsRandomly({
    bool isVacationMode = false,
  }) async {
    if (recipes.isEmpty) {
      return const FillPlanningResult(addedMealsCount: 0, hasRecipes: false);
    }

    final emptySlots = mealSlots.where((slot) {
      return !weeklyPlanning.containsKey(slot.id);
    }).toList();

    if (emptySlots.isEmpty) {
      return const FillPlanningResult(addedMealsCount: 0, hasRecipes: true);
    }

    final random = Random();

    final recipeUsageCounts = <String, int>{
      for (final recipe in recipes) recipe.id: 0,
    };

    for (final planningValue in weeklyPlanning.values) {
      for (final recipeId in getRecipeIdsFromPlanningValue(planningValue)) {
        if (recipeUsageCounts.containsKey(recipeId)) {
          recipeUsageCounts[recipeId] = recipeUsageCounts[recipeId]! + 1;
        }
      }
    }

    final plannedMainGroups = <String, String>{};

    for (final entry in weeklyPlanning.entries) {
      final recipeId = getMainRecipeIdFromPlanningValue(entry.value);
      final recipe = recipeId == null ? null : getRecipeById(recipeId);
      final mainGroup = recipe == null ? null : getMainIngredientGroup(recipe);

      if (mainGroup != null) {
        plannedMainGroups[entry.key] = mainGroup;
      }
    }

    for (final slot in emptySlots) {
      final previousMainGroup = getPreviousMainIngredientGroup(
        slot: slot,
        plannedMainGroups: plannedMainGroups,
      );
      final sameDayMainGroups = getSameDayMainIngredientGroups(
        slot: slot,
        plannedMainGroups: plannedMainGroups,
      );
      final selectedRecipe = chooseRecipeForSlot(
        slot: slot,
        recipeUsageCounts: recipeUsageCounts,
        previousMainGroup: previousMainGroup,
        sameDayMainGroups: sameDayMainGroups,
        isVacationMode: isVacationMode,
        random: random,
      );
      final selectedAccompaniment = chooseAccompanimentForSlot(
        slot: slot,
        mainRecipe: selectedRecipe,
        recipeUsageCounts: recipeUsageCounts,
        isVacationMode: isVacationMode,
        random: random,
      );

      weeklyPlanning[slot.id] = buildRecipePlanningValue(
        recipeId: selectedRecipe.id,
        accompanimentRecipeId: selectedAccompaniment?.id,
      );
      recipeUsageCounts[selectedRecipe.id] =
          recipeUsageCounts[selectedRecipe.id]! + 1;

      if (selectedAccompaniment != null) {
        recipeUsageCounts[selectedAccompaniment.id] =
            recipeUsageCounts[selectedAccompaniment.id]! + 1;
      }

      final selectedMainGroup = getMainIngredientGroup(selectedRecipe);

      if (selectedMainGroup != null) {
        plannedMainGroups[slot.id] = selectedMainGroup;
      }
    }

    checkedShoppingItems.clear();

    await saveData();

    return FillPlanningResult(
      addedMealsCount: emptySlots.length,
      hasRecipes: true,
    );
  }

  Recipe chooseRecipeForSlot({
    required MealSlot slot,
    required Map<String, int> recipeUsageCounts,
    required String? previousMainGroup,
    required Set<String> sameDayMainGroups,
    required bool isVacationMode,
    required Random random,
  }) {
    final mainRecipes = recipes.where((recipe) {
      return !recipe.tags.contains('Accompagnement') &&
          !recipe.tags.contains('Dessert');
    }).toList();
    final shuffledRecipes = [...mainRecipes.isEmpty ? recipes : mainRecipes]
      ..shuffle(random);

    Recipe? bestRecipe;
    int? bestScore;

    for (final recipe in shuffledRecipes) {
      final score = getRecipeScoreForSlot(
        recipe: recipe,
        slot: slot,
        recipeUsageCounts: recipeUsageCounts,
        previousMainGroup: previousMainGroup,
        sameDayMainGroups: sameDayMainGroups,
        isVacationMode: isVacationMode,
      );

      if (bestRecipe == null || score < bestScore!) {
        bestRecipe = recipe;
        bestScore = score;
      }
    }

    return bestRecipe!;
  }

  int getRecipeScoreForSlot({
    required Recipe recipe,
    required MealSlot slot,
    required Map<String, int> recipeUsageCounts,
    required String? previousMainGroup,
    required Set<String> sameDayMainGroups,
    required bool isVacationMode,
  }) {
    final usageCount = recipeUsageCounts[recipe.id] ?? 0;

    // La répartition reste la priorité principale.
    final usageScore = usageCount * 100;

    final typeScore = getRecipeTypePreferenceScore(recipe);
    final repetitionScore = getMainIngredientRepetitionScore(
      recipe: recipe,
      previousMainGroup: previousMainGroup,
      sameDayMainGroups: sameDayMainGroups,
    );

    final timeScore = isWeekendSlot(slot)
        ? getWeekendTimeScore(recipe)
        : getWeekdayTimeScore(recipe, slot);

    final seasonalityScore = getSeasonalityPreferenceScore(recipe);
    final vacationScore = isVacationMode
        ? getVacationCompatibilityScore(recipe)
        : 0;
    final recentHistoryScore = getRecentHistoryScore(recipe);

    return usageScore +
        typeScore +
        repetitionScore +
        timeScore +
        seasonalityScore +
        vacationScore +
        recentHistoryScore;
  }

  int getRecentHistoryScore(Recipe recipe) {
    final cutoffDate = DateTime.now().subtract(const Duration(days: 21));
    final recentCount = mealHistoryEntries.where((entry) {
      return entry.recipeId == recipe.id && entry.cookedAt.isAfter(cutoffDate);
    }).length;

    return recentCount * 80;
  }

  Recipe? chooseAccompanimentForSlot({
    required MealSlot slot,
    required Recipe mainRecipe,
    required Map<String, int> recipeUsageCounts,
    required bool isVacationMode,
    required Random random,
  }) {
    if (mainRecipe.tags.contains('Plat complet')) {
      return null;
    }

    final accompanimentRecipes = recipes.where((recipe) {
      return recipe.id != mainRecipe.id &&
          recipe.tags.contains('Accompagnement');
    }).toList();

    if (accompanimentRecipes.isEmpty) {
      return null;
    }

    final mainGroup = getMainIngredientGroup(mainRecipe);
    final shuffledRecipes = [...accompanimentRecipes]..shuffle(random);

    Recipe? bestRecipe;
    int? bestScore;

    for (final recipe in shuffledRecipes) {
      final usageCount = recipeUsageCounts[recipe.id] ?? 0;
      final recipeGroup = getMainIngredientGroup(recipe);
      final sameBaseScore = recipeGroup != null && recipeGroup == mainGroup
          ? 35
          : 0;
      final timeScore = isWeekendSlot(slot)
          ? getWeekendTimeScore(recipe) ~/ 2
          : getWeekdayTimeScore(recipe, slot) ~/ 2;
      final vacationScore = isVacationMode
          ? getVacationCompatibilityScore(recipe)
          : 0;
      final score =
          usageCount * 100 +
          sameBaseScore +
          timeScore +
          getSeasonalityPreferenceScore(recipe) +
          vacationScore;

      if (bestRecipe == null || score < bestScore!) {
        bestRecipe = recipe;
        bestScore = score;
      }
    }

    return bestRecipe;
  }

  int getRecipeTypePreferenceScore(Recipe recipe) {
    final hasFullDishTag = recipe.tags.contains('Plat complet');
    final hasMainDishTag = recipe.tags.contains('Plat principal');
    final hasSideDishTag = recipe.tags.contains('Accompagnement');
    final hasStarterTag = normalizeForPlanning(
      recipe.tags.join(' '),
    ).contains('entree');
    final hasDessertTag = recipe.tags.contains('Dessert');

    if (hasFullDishTag) {
      return -35;
    }

    if (hasMainDishTag) {
      return -25;
    }

    if (!hasSideDishTag && !hasStarterTag && !hasDessertTag) {
      return 10;
    }

    return 80;
  }

  bool isWeekendSlot(MealSlot slot) {
    return slot.day == 'Samedi' || slot.day == 'Dimanche';
  }

  int getWeekdayTimeScore(Recipe recipe, MealSlot slot) {
    final prepTime = recipe.prepTimeMinutes ?? recipe.durationMinutes ?? 30;
    final totalTime = recipe.durationMinutes ?? prepTime;

    var score = 0;

    if (slot.meal == 'Midi') {
      if (prepTime <= 20) {
        score -= 20;
      } else if (prepTime <= 30) {
        score += 0;
      } else if (prepTime <= 45) {
        score += 35;
      } else {
        score += 80;
      }

      if (totalTime > 60) {
        score += 25;
      }
    } else {
      if (prepTime <= 20) {
        score -= 16;
      } else if (prepTime <= 30) {
        score -= 6;
      } else if (prepTime <= 45) {
        score += 10;
      } else {
        score += 55;
      }

      if (totalTime > 90) {
        score += 55;
      }
    }

    return score;
  }

  int getWeekendTimeScore(Recipe recipe) {
    final prepTime = recipe.prepTimeMinutes ?? recipe.durationMinutes ?? 30;
    final cookTime = recipe.cookTimeMinutes ?? 0;
    final totalTime = recipe.durationMinutes ?? prepTime;

    var score = 0;

    if (totalTime >= 60 || cookTime >= 45) {
      score -= 12;
    } else if (totalTime >= 40) {
      score -= 6;
    }

    if (prepTime > 60) {
      score += 10;
    }

    return score;
  }

  int getSeasonalityPreferenceScore(Recipe recipe) {
    final seasonality = SeasonalityService.analyzeRecipe(recipe);

    if (!seasonality.hasProduceIngredients) {
      return 0;
    }

    if (seasonality.isFullySeasonal) {
      return -18;
    }

    if (seasonality.score >= 50) {
      return -6;
    }

    return 8;
  }

  int getVacationCompatibilityScore(Recipe recipe) {
    final hasOven = recipe.tags.contains('Four');
    final hasStovetop = recipe.tags.contains('Plaque de cuisson');
    final hasNoCook = recipe.tags.contains('Sans cuisson');

    var score = 0;

    if (hasNoCook) {
      score -= 22;
    }

    if (hasStovetop) {
      score -= 8;
    }

    if (hasOven) {
      score += 75;
    }

    return score;
  }

  int getMainIngredientRepetitionScore({
    required Recipe recipe,
    required String? previousMainGroup,
    required Set<String> sameDayMainGroups,
  }) {
    final mainGroup = getMainIngredientGroup(recipe);

    if (mainGroup == null) {
      return 0;
    }

    var score = 0;

    if (mainGroup == previousMainGroup) {
      score += 60;
    }

    if (sameDayMainGroups.contains(mainGroup)) {
      score += 30;
    }

    return score;
  }

  String? getPreviousMainIngredientGroup({
    required MealSlot slot,
    required Map<String, String> plannedMainGroups,
  }) {
    final slotIndex = mealSlots.indexWhere((item) => item.id == slot.id);

    if (slotIndex <= 0) {
      return null;
    }

    for (var index = slotIndex - 1; index >= 0; index--) {
      final group = plannedMainGroups[mealSlots[index].id];

      if (group != null) {
        return group;
      }
    }

    return null;
  }

  Set<String> getSameDayMainIngredientGroups({
    required MealSlot slot,
    required Map<String, String> plannedMainGroups,
  }) {
    return mealSlots
        .where((item) {
          return item.day == slot.day && item.id != slot.id;
        })
        .map((item) {
          return plannedMainGroups[item.id];
        })
        .whereType<String>()
        .toSet();
  }

  String? getMainIngredientGroup(Recipe recipe) {
    final searchableText = normalizeForPlanning(
      [
        recipe.name,
        recipe.tags.join(' '),
        recipe.ingredients.map((ingredient) => ingredient.name).join(' '),
      ].join(' '),
    );

    const ingredientGroups = <String, List<String>>{
      'poulet': ['poulet', 'dinde', 'volaille'],
      'boeuf': ['boeuf', 'steak', 'hach'],
      'porc': ['porc', 'jambon', 'lardon', 'saucisse', 'chorizo'],
      'poisson': ['poisson', 'cabillaud', 'colin', 'merlu'],
      'saumon': ['saumon'],
      'thon': ['thon'],
      'crevette': ['crevette', 'gambas'],
      'oeuf': ['oeuf', 'omelette'],
      'legumineuse': ['lentille', 'pois chiche', 'haricot rouge'],
      'pates': ['pate', 'spaghetti', 'tagliatelle', 'macaroni'],
      'riz': ['riz', 'risotto'],
    };

    for (final entry in ingredientGroups.entries) {
      for (final keyword in entry.value) {
        if (searchableText.contains(keyword)) {
          return entry.key;
        }
      }
    }

    return null;
  }

  String normalizeForPlanning(String value) {
    final buffer = StringBuffer();

    for (final rune in value.toLowerCase().runes) {
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

  Future<void> toggleShoppingItem(String ingredient, bool isChecked) async {
    if (isChecked) {
      checkedShoppingItems.add(ingredient);
    } else {
      checkedShoppingItems.remove(ingredient);
    }

    await saveData();
  }
}
