import 'package:flutter/material.dart';

import '../controllers/cuisine_controller.dart';
import '../data/meal_slots.dart';
import '../models/recipe.dart';
import '../services/storage_service.dart';
import 'backup_screen.dart';
import 'import_recipe_screen.dart';
import 'import_recipe_url_screen.dart';
import 'planning_screen.dart';
import 'recipe_form_screen.dart';
import 'recipes_screen.dart';
import 'shopping_list_screen.dart';

enum AddRecipeMode { manual, importText, importUrl }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.onBackToHub});

  final VoidCallback? onBackToHub;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final cuisineController = CuisineController();

  int selectedIndex = 0;

  final List<String> titles = const [
    'Mes recettes',
    'Planning de la semaine',
    'Liste de courses',
  ];

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    await cuisineController.loadData();

    if (!mounted) {
      return;
    }

    setState(() {});
  }

  void onDestinationSelected(int index) {
    setState(() {
      selectedIndex = index;
    });
  }

  void showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> openBackupScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) {
          return BackupScreen(
            appData: cuisineController.appData,
            getAppData: () => cuisineController.appData,
            onRestoreData: restoreDataFromBackup,
            onMergeData: mergeDataFromBackup,
          );
        },
      ),
    );
  }

  Future<void> restoreDataFromBackup(AppData importedData) async {
    await cuisineController.restoreDataFromBackup(importedData);

    if (!mounted) {
      return;
    }

    setState(() {
      selectedIndex = 0;
    });
  }

  Future<MergeBackupResult> mergeDataFromBackup(
    AppData importedData, {
    MergePlanningMode planningMode = MergePlanningMode.fillEmptySlots,
  }) async {
    final result = await cuisineController.mergeDataFromBackup(
      importedData,
      planningMode: planningMode,
    );

    if (!mounted) {
      return result;
    }

    setState(() {
      selectedIndex = 0;
    });

    return result;
  }

  Future<void> openAddRecipeScreen() async {
    final selectedMode = await showModalBottomSheet<AddRecipeMode>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Ajouter une recette',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: const Text('Ajouter manuellement'),
                    subtitle: const Text('Créer une recette champ par champ.'),
                    onTap: () {
                      Navigator.of(context).pop(AddRecipeMode.manual);
                    },
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.auto_fix_high_outlined),
                    title: const Text('Coller une recette'),
                    subtitle: const Text(
                      'Analyser un texte ou une liste d’ingrédients.',
                    ),
                    onTap: () {
                      Navigator.of(context).pop(AddRecipeMode.importText);
                    },
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.link),
                    title: const Text('Importer depuis un lien'),
                    subtitle: const Text(
                      'Pré-remplir depuis une page de recette compatible.',
                    ),
                    onTap: () {
                      Navigator.of(context).pop(AddRecipeMode.importUrl);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    switch (selectedMode) {
      case AddRecipeMode.manual:
        await openManualRecipeForm();
      case AddRecipeMode.importText:
        await openImportRecipeFlow();
      case AddRecipeMode.importUrl:
        await openImportRecipeUrlFlow();
      case null:
        return;
    }
  }

  Future<void> openImportRecipeUrlFlow() async {
    final draftRecipe = await Navigator.of(context).push<Recipe>(
      MaterialPageRoute(
        builder: (context) {
          return const ImportRecipeUrlScreen();
        },
      ),
    );

    if (draftRecipe == null || !mounted) {
      return;
    }

    final newRecipe = await Navigator.of(context).push<Recipe>(
      MaterialPageRoute(
        builder: (context) {
          return RecipeFormScreen(initialRecipe: draftRecipe, isDraft: true);
        },
      ),
    );

    if (newRecipe == null) {
      return;
    }

    await addRecipe(newRecipe);
  }

  Future<void> openManualRecipeForm() async {
    final newRecipe = await Navigator.of(context).push<Recipe>(
      MaterialPageRoute(
        builder: (context) {
          return const RecipeFormScreen();
        },
      ),
    );

    if (newRecipe == null) {
      return;
    }

    await addRecipe(newRecipe);
  }

  Future<void> openImportRecipeFlow() async {
    final draftRecipe = await Navigator.of(context).push<Recipe>(
      MaterialPageRoute(
        builder: (context) {
          return const ImportRecipeScreen();
        },
      ),
    );

    if (draftRecipe == null || !mounted) {
      return;
    }

    final newRecipe = await Navigator.of(context).push<Recipe>(
      MaterialPageRoute(
        builder: (context) {
          return RecipeFormScreen(initialRecipe: draftRecipe, isDraft: true);
        },
      ),
    );

    if (newRecipe == null) {
      return;
    }

    await addRecipe(newRecipe);
  }

  Future<void> addRecipe(Recipe newRecipe) async {
    await cuisineController.addRecipe(newRecipe);

    if (!mounted) {
      return;
    }

    setState(() {});
    showSnackBar('Recette ajoutée : ${newRecipe.name}');
  }

  Future<void> openEditRecipeScreen(Recipe recipeToEdit) async {
    final updatedRecipe = await Navigator.of(context).push<Recipe>(
      MaterialPageRoute(
        builder: (context) {
          return RecipeFormScreen(initialRecipe: recipeToEdit);
        },
      ),
    );

    if (updatedRecipe == null) {
      return;
    }

    await cuisineController.updateRecipe(updatedRecipe);

    if (!mounted) {
      return;
    }

    setState(() {});
    showSnackBar('Recette modifiée : ${updatedRecipe.name}');
  }

  Future<void> deleteRecipe(Recipe recipeToDelete) async {
    await cuisineController.deleteRecipe(recipeToDelete);

    if (!mounted) {
      return;
    }

    setState(() {});
    showSnackBar('Recette supprimée : ${recipeToDelete.name}');
  }

  Future<void> updateSafeIngredientCategories() async {
    final result = await cuisineController.updateSafeIngredientCategories();

    if (!mounted) {
      return;
    }

    setState(() {});

    if (!result.hasUpdates) {
      showSnackBar('Aucune catégorie à reclasser.');
      return;
    }

    showSnackBar(
      '${result.updatedIngredientsCount} ingrédient(s) reclassé(s) '
      'dans ${result.updatedRecipesCount} recette(s).',
    );
  }

  Future<void> updatePantryIngredientNames(
    Iterable<String> pantryIngredientNames,
  ) async {
    await cuisineController.updatePantryIngredientNames(pantryIngredientNames);

    if (!mounted) {
      return;
    }

    setState(() {});
    showSnackBar('Stock maison mis à jour.');
  }

  Future<void> setSpecialMealForSlot(String slotId, String label) async {
    final specialMealLabel = await cuisineController.setSpecialMealForSlot(
      slotId,
      label,
    );

    if (!mounted) {
      return;
    }

    setState(() {});
    showSnackBar('$specialMealLabel ajouté pour ${getMealSlotLabel(slotId)}');
  }

  Future<void> selectAccompanimentForSlot(
    String slotId,
    Recipe accompanimentRecipe,
  ) async {
    final result = await cuisineController.selectAccompanimentForSlot(
      slotId,
      accompanimentRecipe,
    );

    if (!mounted) {
      return;
    }

    switch (result) {
      case SelectAccompanimentResult.added:
        setState(() {});
        showSnackBar('Accompagnement ajouté : ${accompanimentRecipe.name}');
      case SelectAccompanimentResult.fullDish:
        showSnackBar(
          'Ce plat est marqué comme plat complet : pas besoin d’accompagnement.',
        );
      case SelectAccompanimentResult.missingMainRecipe:
        return;
    }
  }

  Future<void> removeAccompanimentFromSlot(String slotId) async {
    await cuisineController.removeAccompanimentFromSlot(slotId);

    if (!mounted) {
      return;
    }

    setState(() {});
    showSnackBar('Accompagnement retiré.');
  }

  Future<void> selectRecipeForSlot(String slotId, Recipe recipe) async {
    await cuisineController.selectRecipeForSlot(slotId, recipe);

    if (!mounted) {
      return;
    }

    setState(() {});
    showSnackBar('${recipe.name} ajoutée pour ${getMealSlotLabel(slotId)}');
  }

  Future<void> removeRecipeFromSlot(String slotId) async {
    await cuisineController.removeRecipeFromSlot(slotId);

    if (!mounted) {
      return;
    }

    setState(() {});
    showSnackBar('Recette retirée pour ${getMealSlotLabel(slotId)}');
  }

  Future<void> resetWeek() async {
    await cuisineController.resetWeek();

    if (!mounted) {
      return;
    }

    setState(() {});
    showSnackBar('La semaine a été réinitialisée.');
  }

  Future<bool> recordCookedRecipe({
    required Recipe recipe,
    required DateTime cookedAt,
    required String mealLabel,
    String? sourcePlanningSlotId,
  }) async {
    final result = await cuisineController.recordCookedRecipe(
      recipe: recipe,
      cookedAt: cookedAt,
      mealLabel: mealLabel,
      sourcePlanningSlotId: sourcePlanningSlotId,
    );

    if (!mounted) {
      return result.wasAdded;
    }

    setState(() {});

    return result.wasAdded;
  }

  Future<void> fillEmptySlotsRandomly({bool isVacationMode = false}) async {
    final result = await cuisineController.fillEmptySlotsRandomly(
      isVacationMode: isVacationMode,
    );

    if (!mounted) {
      return;
    }

    if (!result.hasRecipes) {
      showSnackBar('Ajoute au moins une recette avant de remplir le planning.');
      return;
    }

    if (result.isPlanningAlreadyFull) {
      showSnackBar('Le planning est déjà complet.');
      return;
    }

    setState(() {});
    showSnackBar(
      '${result.addedMealsCount} repas ajouté(s) avec un remplissage intelligent.',
    );
  }

  Future<void> toggleShoppingItem(String ingredient, bool isChecked) async {
    await cuisineController.toggleShoppingItem(ingredient, isChecked);

    if (!mounted) {
      return;
    }

    setState(() {});
  }

  void goToRecipes() {
    setState(() {
      selectedIndex = 0;
    });
  }

  void goToPlanning() {
    setState(() {
      selectedIndex = 1;
    });
  }

  Widget buildCurrentScreen() {
    if (cuisineController.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    switch (selectedIndex) {
      case 0:
        return RecipesScreen(
          recipes: cuisineController.recipes,
          onAddRecipe: openAddRecipeScreen,
          onEditRecipe: openEditRecipeScreen,
          onDeleteRecipe: deleteRecipe,
          onRecordCookedRecipe: recordCookedRecipe,
        );
      case 1:
        return PlanningScreen(
          recipes: cuisineController.recipes,
          weeklyPlanning: cuisineController.weeklyPlanning,
          onSelectRecipe: selectRecipeForSlot,
          onSetSpecialMeal: setSpecialMealForSlot,
          onRemoveRecipe: removeRecipeFromSlot,
          onResetWeek: resetWeek,
          onFillEmptySlots: fillEmptySlotsRandomly,
          onSelectAccompaniment: selectAccompanimentForSlot,
          onRemoveAccompaniment: removeAccompanimentFromSlot,
          onGoToRecipes: goToRecipes,
          mealHistoryEntries: cuisineController.mealHistoryEntries,
          onRecordCookedRecipe: recordCookedRecipe,
        );
      case 2:
        return ShoppingListScreen(
          recipes: cuisineController.recipes,
          weeklyPlanning: cuisineController.weeklyPlanning,
          checkedShoppingItems: cuisineController.checkedShoppingItems,
          onToggleItem: toggleShoppingItem,
          onGoToPlanning: goToPlanning,
          onEditRecipe: openEditRecipeScreen,
          ingredientCategoryUpdateCount: cuisineController
              .countSafeIngredientCategoryUpdates(),
          onUpdateIngredientCategories: updateSafeIngredientCategories,
          pantryIngredientNames: cuisineController.pantryIngredientNames,
          onUpdatePantryIngredientNames: updatePantryIngredientNames,
        );
      default:
        return RecipesScreen(
          recipes: cuisineController.recipes,
          onAddRecipe: openAddRecipeScreen,
          onEditRecipe: openEditRecipeScreen,
          onDeleteRecipe: deleteRecipe,
          onRecordCookedRecipe: recordCookedRecipe,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: widget.onBackToHub == null
            ? null
            : IconButton(
                tooltip: 'Accueil',
                onPressed: widget.onBackToHub,
                icon: const Icon(Icons.home_outlined),
              ),
        title: Text(titles[selectedIndex]),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Sauvegarde',
            onPressed: cuisineController.isLoading ? null : openBackupScreen,
            icon: const Icon(Icons.backup_outlined),
          ),
        ],
      ),
      body: buildCurrentScreen(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.restaurant_menu),
            label: 'Recettes',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month),
            label: 'Planning',
          ),
          NavigationDestination(
            icon: Icon(Icons.shopping_cart),
            label: 'Courses',
          ),
        ],
      ),
    );
  }
}
