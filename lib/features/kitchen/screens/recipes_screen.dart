import 'package:flutter/material.dart';

import '../data/recipe_review_statuses.dart';
import '../data/seasonal_ingredients.dart';
import '../services/seasonality_service.dart';
import '../models/recipe.dart';
import 'recipe_detail_screen.dart';

class RecipesScreen extends StatefulWidget {
  const RecipesScreen({
    super.key,
    required this.recipes,
    required this.onAddRecipe,
    required this.onEditRecipe,
    required this.onDeleteRecipe,
    required this.onRecordCookedRecipe,
  });

  final List<Recipe> recipes;
  final VoidCallback onAddRecipe;
  final Future<void> Function(Recipe recipe) onEditRecipe;
  final Future<void> Function(Recipe recipe) onDeleteRecipe;
  final Future<bool> Function({
    required Recipe recipe,
    required DateTime cookedAt,
    required String mealLabel,
    String? sourcePlanningSlotId,
  })
  onRecordCookedRecipe;

  @override
  State<RecipesScreen> createState() => _RecipesScreenState();
}

class _RecipesScreenState extends State<RecipesScreen> {
  final searchController = TextEditingController();

  String searchQuery = '';
  bool showSeasonalOnly = false;

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  List<Recipe> get filteredRecipes {
    final query = searchQuery.trim().toLowerCase();

    final recipes = widget.recipes.where((recipe) {
      final matchesSearch = query.isEmpty || recipeMatchesSearch(recipe, query);
      final matchesSeason = !showSeasonalOnly || isRecipeSeasonal(recipe);

      return matchesSearch && matchesSeason;
    }).toList();

    recipes.sort((a, b) {
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return recipes;
  }

  bool recipeMatchesSearch(Recipe recipe, String query) {
    final recipeName = recipe.name.toLowerCase();
    final recipeSteps = recipe.steps.toLowerCase();
    final recipeTags = recipe.tags.join(' ').toLowerCase();

    final recipeMetadata =
        '${recipe.prepTimeMinutes ?? ''} ${recipe.cookTimeMinutes ?? ''} '
                '${recipe.prepTimeText} ${recipe.cookTimeText} ${recipe.durationText} '
                '${recipe.ratingText} ${recipe.reviewStatus}'
            .toLowerCase();

    final ingredientsText = recipe.ingredients
        .map(
          (ingredient) =>
              '${ingredient.name} ${ingredient.unit} ${ingredient.category}',
        )
        .join(' ')
        .toLowerCase();

    return recipeName.contains(query) ||
        recipeSteps.contains(query) ||
        recipeTags.contains(query) ||
        recipeMetadata.contains(query) ||
        ingredientsText.contains(query);
  }

  bool isRecipeSeasonal(Recipe recipe) {
    final seasonality = SeasonalityService.analyzeRecipe(recipe);

    return seasonality.isFullySeasonal;
  }

  List<String> getSeasonalMatchesForRecipe(Recipe recipe) {
    return SeasonalityService.analyzeRecipe(recipe).seasonalMatches;
  }

  Future<void> confirmDeleteRecipe(BuildContext context, Recipe recipe) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Supprimer la recette ?'),
          content: Text(
            'La recette "${recipe.name}" sera supprimée. '
            'Elle sera aussi retirée du planning si elle y est utilisée.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              child: const Text('Supprimer'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) {
      return;
    }

    await widget.onDeleteRecipe(recipe);
  }

  Future<void> openRecipeDetail(Recipe recipe) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) {
          return RecipeDetailScreen(
            recipe: recipe,
            recipes: widget.recipes,
            onEditRecipe: widget.onEditRecipe,
            onDeleteRecipe: widget.onDeleteRecipe,
            onRecordCookedRecipe: widget.onRecordCookedRecipe,
          );
        },
      ),
    );
  }

  void updateSearchQuery(String value) {
    setState(() {
      searchQuery = value;
    });
  }

  void clearSearch() {
    searchController.clear();

    setState(() {
      searchQuery = '';
    });
  }

  void toggleSeasonalFilter(bool value) {
    setState(() {
      showSeasonalOnly = value;
    });
  }

  Future<void> showSeasonalIngredientsDialog(BuildContext context) async {
    final monthName = getCurrentSeasonMonthName();
    final seasonalIngredients = getCurrentSeasonalIngredients();

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Produits de saison — $monthName'),
          content: SingleChildScrollView(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final ingredient in seasonalIngredients)
                  Chip(
                    label: Text(ingredient),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Fermer'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final recipes = filteredRecipes;
    final hasSearch = searchQuery.trim().isNotEmpty;
    final monthName = getCurrentSeasonMonthName();
    final seasonalRecipeCount = widget.recipes.where(isRecipeSeasonal).length;

    if (widget.recipes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: _EmptyRecipesCard(onAddRecipe: widget.onAddRecipe),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _RecipesHeader(
          totalRecipeCount: widget.recipes.length,
          seasonalRecipeCount: seasonalRecipeCount,
          monthName: monthName,
          onAddRecipe: widget.onAddRecipe,
        ),
        const SizedBox(height: 16),
        _SearchAndFiltersCard(
          searchController: searchController,
          searchQuery: searchQuery,
          showSeasonalOnly: showSeasonalOnly,
          monthName: monthName,
          onSearchChanged: updateSearchQuery,
          onClearSearch: clearSearch,
          onSeasonalChanged: toggleSeasonalFilter,
          onShowSeasonalIngredients: () async {
            await showSeasonalIngredientsDialog(context);
          },
        ),
        const SizedBox(height: 12),
        _ResultsSummary(
          filteredCount: recipes.length,
          totalCount: widget.recipes.length,
          seasonalRecipeCount: seasonalRecipeCount,
          hasSearch: hasSearch,
          showSeasonalOnly: showSeasonalOnly,
        ),
        const SizedBox(height: 12),
        if (recipes.isEmpty)
          _NoResultsCard(
            searchQuery: searchQuery,
            showSeasonalOnly: showSeasonalOnly,
            monthName: monthName,
            onClearSearch: clearSearch,
            onDisableSeasonalFilter: () {
              toggleSeasonalFilter(false);
            },
          ),
        for (final recipe in recipes)
          _RecipeListCard(
            recipe: recipe,
            seasonalMatches: getSeasonalMatchesForRecipe(recipe),
            onOpenDetails: openRecipeDetail,
            onEditRecipe: widget.onEditRecipe,
            onDeleteRecipe: (recipe) async {
              await confirmDeleteRecipe(context, recipe);
            },
          ),
      ],
    );
  }
}

class _RecipesHeader extends StatelessWidget {
  const _RecipesHeader({
    required this.totalRecipeCount,
    required this.seasonalRecipeCount,
    required this.monthName,
    required this.onAddRecipe,
  });

  final int totalRecipeCount;
  final int seasonalRecipeCount;
  final String monthName;
  final VoidCallback onAddRecipe;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 58,
                height: 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.menu_book_outlined,
                  size: 32,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Mes recettes',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onPrimaryContainer,
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '$totalRecipeCount recette(s) enregistrée(s)',
            style: TextStyle(
              color: colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$seasonalRecipeCount de saison en $monthName',
            style: TextStyle(
              color: colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: onAddRecipe,
              icon: const Icon(Icons.add),
              label: const Text('Ajouter une recette'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchAndFiltersCard extends StatelessWidget {
  const _SearchAndFiltersCard({
    required this.searchController,
    required this.searchQuery,
    required this.showSeasonalOnly,
    required this.monthName,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onSeasonalChanged,
    required this.onShowSeasonalIngredients,
  });

  final TextEditingController searchController;
  final String searchQuery;
  final bool showSeasonalOnly;
  final String monthName;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<bool> onSeasonalChanged;
  final Future<void> Function() onShowSeasonalIngredients;

  @override
  Widget build(BuildContext context) {
    final hasSearch = searchQuery.trim().isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: searchController,
              decoration: InputDecoration(
                labelText: 'Rechercher',
                hintText: 'Nom, ingrédient, tag, difficulté...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: hasSearch
                    ? IconButton(
                        onPressed: onClearSearch,
                        icon: const Icon(Icons.close),
                      )
                    : null,
              ),
              onChanged: onSearchChanged,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilterChip(
                    label: Text('De saison — $monthName'),
                    selected: showSeasonalOnly,
                    avatar: const Icon(Icons.eco_outlined, size: 18),
                    onSelected: onSeasonalChanged,
                  ),
                  OutlinedButton.icon(
                    onPressed: onShowSeasonalIngredients,
                    icon: const Icon(Icons.info_outline),
                    label: const Text('Produits'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultsSummary extends StatelessWidget {
  const _ResultsSummary({
    required this.filteredCount,
    required this.totalCount,
    required this.seasonalRecipeCount,
    required this.hasSearch,
    required this.showSeasonalOnly,
  });

  final int filteredCount;
  final int totalCount;
  final int seasonalRecipeCount;
  final bool hasSearch;
  final bool showSeasonalOnly;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    String text;

    if (showSeasonalOnly) {
      text =
          '$filteredCount/$seasonalRecipeCount recette(s) de saison affichée(s)';
    } else if (hasSearch) {
      text = '$filteredCount/$totalCount recette(s) trouvée(s)';
    } else {
      text = '$totalCount recette(s)';
    }

    return Text(
      text,
      style: TextStyle(
        color: colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _RecipeListCard extends StatelessWidget {
  const _RecipeListCard({
    required this.recipe,
    required this.seasonalMatches,
    required this.onOpenDetails,
    required this.onEditRecipe,
    required this.onDeleteRecipe,
  });

  final Recipe recipe;
  final List<String> seasonalMatches;
  final Future<void> Function(Recipe recipe) onOpenDetails;
  final Future<void> Function(Recipe recipe) onEditRecipe;
  final Future<void> Function(Recipe recipe) onDeleteRecipe;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final seasonality = SeasonalityService.analyzeRecipe(recipe);
    final needsReview = recipe.reviewStatus == defaultRecipeReviewStatus;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () async {
          await onOpenDetails(recipe);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Text(
                      recipe.emoji,
                      style: const TextStyle(fontSize: 25),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      recipe.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Actions',
                    onSelected: (value) async {
                      if (value == 'edit') {
                        await onEditRecipe(recipe);
                      }

                      if (value == 'delete') {
                        await onDeleteRecipe(recipe);
                      }
                    },
                    itemBuilder: (context) {
                      return const [
                        PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit_outlined),
                              SizedBox(width: 8),
                              Text('Modifier'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline),
                              SizedBox(width: 8),
                              Text('Supprimer'),
                            ],
                          ),
                        ),
                      ];
                    },
                  ),
                ],
              ),
              if (needsReview) ...[
                const SizedBox(height: 8),
                const _ImportedRecipeWarning(),
              ],
              if (recipe.timeSummaryText.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  recipe.timeSummaryText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ],
              if (recipe.tags.isNotEmpty ||
                  seasonality.hasProduceIngredients ||
                  (!needsReview && recipe.reviewStatus.isNotEmpty) ||
                  recipe.ratingText.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (seasonality.hasProduceIngredients)
                      _CompactChip(
                        icon: Icons.eco_outlined,
                        label: '${seasonality.score}% saison',
                      ),
                    if (!needsReview)
                      _CompactChip(
                        icon: Icons.fact_check_outlined,
                        label: recipe.reviewStatus,
                      ),
                    if (recipe.ratingText.isNotEmpty)
                      _CompactChip(
                        icon: Icons.star_rate_outlined,
                        label: recipe.ratingText,
                      ),
                    for (final tag in recipe.tags.take(3))
                      Chip(
                        label: Text(tag),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    if (recipe.tags.length > 3)
                      Chip(
                        label: Text('+${recipe.tags.length - 3}'),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ImportedRecipeWarning extends StatelessWidget {
  const _ImportedRecipeWarning();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.warning_amber_outlined,
            size: 17,
            color: colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 6),
          Text(
            'À relire',
            style: TextStyle(
              color: colorScheme.onErrorContainer,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactChip extends StatelessWidget {
  const _CompactChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _NoResultsCard extends StatelessWidget {
  const _NoResultsCard({
    required this.searchQuery,
    required this.showSeasonalOnly,
    required this.monthName,
    required this.onClearSearch,
    required this.onDisableSeasonalFilter,
  });

  final String searchQuery;
  final bool showSeasonalOnly;
  final String monthName;
  final VoidCallback onClearSearch;
  final VoidCallback onDisableSeasonalFilter;

  @override
  Widget build(BuildContext context) {
    final hasSearch = searchQuery.trim().isNotEmpty;
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.search_off,
                size: 38,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              showSeasonalOnly
                  ? 'Aucune recette de saison trouvée pour $monthName.'
                  : 'Aucune recette trouvée pour "$searchQuery".',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (hasSearch)
                  OutlinedButton.icon(
                    onPressed: onClearSearch,
                    icon: const Icon(Icons.close),
                    label: const Text('Effacer la recherche'),
                  ),
                if (showSeasonalOnly)
                  OutlinedButton.icon(
                    onPressed: onDisableSeasonalFilter,
                    icon: const Icon(Icons.eco_outlined),
                    label: const Text('Désactiver saison'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyRecipesCard extends StatelessWidget {
  const _EmptyRecipesCard({required this.onAddRecipe});

  final VoidCallback onAddRecipe;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.menu_book_outlined,
                size: 38,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Aucune recette',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Ajoute ta première recette pour commencer à remplir ton planning.',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAddRecipe,
              icon: const Icon(Icons.add),
              label: const Text('Ajouter une recette'),
            ),
          ],
        ),
      ),
    );
  }
}
