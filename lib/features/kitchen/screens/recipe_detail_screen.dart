import 'package:flutter/material.dart';

import '../data/seasonal_ingredients.dart';
import '../services/seasonality_service.dart';
import '../models/recipe.dart';
import 'cooking_screen.dart';
import '../data/recipe_tags.dart';

class RecipeDetailScreen extends StatelessWidget {
  const RecipeDetailScreen({
    super.key,
    required this.recipe,
    required this.recipes,
    required this.onEditRecipe,
    required this.onDeleteRecipe,
    this.onRecordCookedRecipe,
  });

  final Recipe recipe;
  final List<Recipe> recipes;
  final Future<void> Function(Recipe recipe) onEditRecipe;
  final Future<void> Function(Recipe recipe) onDeleteRecipe;
  final Future<bool> Function({
    required Recipe recipe,
    required DateTime cookedAt,
    required String mealLabel,
    String? sourcePlanningSlotId,
  })?
  onRecordCookedRecipe;

  List<String> getSeasonalMatchesForRecipe() {
    final seasonalIngredients = getCurrentSeasonalIngredients();
    final matches = <String>{};

    for (final ingredient in recipe.ingredients) {
      for (final seasonalItem in seasonalIngredients) {
        final matchesSeason = ingredientNameMatchesSeasonalItem(
          ingredientName: ingredient.name,
          seasonalItem: seasonalItem,
        );

        if (matchesSeason) {
          matches.add(seasonalItem);
        }
      }
    }

    return matches.toList()..sort();
  }

  int getSeasonalIngredientCount() {
    final seasonalIngredients = getCurrentSeasonalIngredients();

    return recipe.ingredients.where((ingredient) {
      return seasonalIngredients.any((seasonalItem) {
        return ingredientNameMatchesSeasonalItem(
          ingredientName: ingredient.name,
          seasonalItem: seasonalItem,
        );
      });
    }).length;
  }

  Future<void> confirmDeleteRecipe(BuildContext context) async {
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

    await onDeleteRecipe(recipe);

    if (!context.mounted) {
      return;
    }

    Navigator.of(context).pop();
  }

  Future<void> editRecipe(BuildContext context) async {
    await onEditRecipe(recipe);

    if (!context.mounted) {
      return;
    }

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final seasonality = SeasonalityService.analyzeRecipe(recipe);
    final seasonalMatches = seasonality.seasonalMatches;
    final monthName = getCurrentSeasonMonthName();
    final seasonalScore = seasonality.score;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Détail recette'),
        actions: [
          IconButton(
            tooltip: 'Cuisiner',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) {
                    return CookingScreen(
                      recipe: recipe,
                      availableRecipes: recipes,
                      onRecordCooked: onRecordCookedRecipe,
                    );
                  },
                ),
              );
            },
            icon: const Icon(Icons.play_arrow),
          ),
          IconButton(
            tooltip: 'Modifier',
            onPressed: () async {
              await editRecipe(context);
            },
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Supprimer',
            onPressed: () async {
              await confirmDeleteRecipe(context);
            },
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _RecipeHeader(
              recipe: recipe,
              seasonalScore: seasonalScore,
              hasSeasonalIngredients: seasonalMatches.isNotEmpty,
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Résumé',
              icon: Icons.dashboard_outlined,
              child: _RecipeSummaryContent(
                recipe: recipe,
                seasonality: seasonality,
                monthName: monthName,
                onEditRecipe: () async {
                  await editRecipe(context);
                },
              ),
            ),
            if (seasonalMatches.isNotEmpty)
              _SectionCard(
                title: 'De saison en $monthName',
                icon: Icons.eco_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      seasonality.summaryText,
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final ingredient in seasonalMatches)
                          Chip(
                            avatar: const Icon(Icons.eco_outlined, size: 18),
                            label: Text(ingredient),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            _SectionCard(
              title: 'Ingrédients',
              icon: Icons.shopping_basket_outlined,
              child: Column(
                children: [
                  for (
                    int index = 0;
                    index < recipe.ingredients.length;
                    index++
                  )
                    _IngredientRow(
                      text: recipe.ingredients[index].displayText,
                      category: recipe.ingredients[index].category,
                      includeInShoppingList:
                          recipe.ingredients[index].includeInShoppingList,
                      isLast: index == recipe.ingredients.length - 1,
                    ),
                ],
              ),
            ),
            _SectionCard(
              title: 'Préparation',
              icon: Icons.notes_outlined,
              child: _PreparationStepsList(
                steps: splitPreparationSteps(recipe.steps),
              ),
            ),
            const SizedBox(height: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) {
                          return CookingScreen(
                            recipe: recipe,
                            availableRecipes: recipes,
                            onRecordCooked: onRecordCookedRecipe,
                          );
                        },
                      ),
                    );
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Démarrer la préparation'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await editRecipe(context);
                        },
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Modifier'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await confirmDeleteRecipe(context);
                        },
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Supprimer'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _RecipeHeader extends StatelessWidget {
  const _RecipeHeader({
    required this.recipe,
    required this.seasonalScore,
    required this.hasSeasonalIngredients,
  });

  final Recipe recipe;
  final int seasonalScore;
  final bool hasSeasonalIngredients;

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
                child: Text(recipe.emoji, style: const TextStyle(fontSize: 34)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  recipe.name,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onPrimaryContainer,
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${recipe.ingredients.length} ingrédient(s)',
                style: TextStyle(
                  color: colorScheme.onPrimaryContainer,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (recipe.timeSummaryText.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  recipe.timeSummaryText,
                  style: TextStyle(
                    color: colorScheme.onPrimaryContainer,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              if (recipe.ratingText.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  recipe.ratingText,
                  style: TextStyle(
                    color: colorScheme.onPrimaryContainer,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                recipe.reviewStatus,
                style: TextStyle(
                  color: colorScheme.onPrimaryContainer,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          if (hasSeasonalIngredients) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '🌱 $seasonalScore% fruits/légumes',
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _IngredientRow extends StatelessWidget {
  const _IngredientRow({
    required this.text,
    required this.category,
    required this.includeInShoppingList,
    required this.isLast,
  });

  final String text;
  final String category;
  final bool includeInShoppingList;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: includeInShoppingList
                    ? colorScheme.primary
                    : colorScheme.outline,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: includeInShoppingList
                      ? colorScheme.onSurface
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              category,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            if (!includeInShoppingList) ...[
              const SizedBox(width: 8),
              Tooltip(
                message: 'Non ajouté aux courses',
                child: Icon(
                  Icons.remove_shopping_cart_outlined,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
        if (!includeInShoppingList)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 20, top: 4),
              child: Text(
                'Non ajouté aux courses',
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ),
        if (!isLast) Divider(height: 20, color: colorScheme.outlineVariant),
      ],
    );
  }
}

List<String> splitPreparationSteps(String steps) {
  final cleanedSteps = steps.trim();

  if (cleanedSteps.isEmpty || cleanedSteps == 'À compléter.') {
    return [];
  }

  if (RegExp(r'\n\s*\n').hasMatch(cleanedSteps)) {
    return cleanedSteps
        .split(RegExp(r'\n\s*\n'))
        .map(cleanPreparationStepBlock)
        .where((step) => step.isNotEmpty && step != 'À compléter.')
        .toList();
  }

  final hasBulletList = RegExp(r'(^|\n)\s*[-•*]\s+').hasMatch(cleanedSteps);

  if (hasBulletList) {
    return [cleanPreparationStepBlock(cleanedSteps)];
  }

  return cleanedSteps
      .split('\n')
      .map(cleanPreparationStep)
      .where((step) => step.isNotEmpty && step != 'À compléter.')
      .toList();
}

String cleanPreparationStep(String value) {
  return value
      .trim()
      .replaceFirst(RegExp(r'^[-•*]\s*'), '')
      .replaceFirst(RegExp(r'^\d+[.)]\s*'), '')
      .trim();
}

String cleanPreparationStepBlock(String value) {
  return value.trim().replaceFirst(RegExp(r'^\d+[.)]\s*'), '').trim();
}

class _PreparationStepsList extends StatelessWidget {
  const _PreparationStepsList({required this.steps});

  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) {
      return const Text('Aucune étape renseignée.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int index = 0; index < steps.length; index++)
          _PreparationStepRow(
            index: index,
            text: steps[index],
            isLast: index == steps.length - 1,
          ),
      ],
    );
  }
}

class _PreparationStepRow extends StatelessWidget {
  const _PreparationStepRow({
    required this.index,
    required this.text,
    required this.isLast,
  });

  final int index;
  final String text;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  height: 1.45,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        if (!isLast) Divider(height: 24, color: colorScheme.outlineVariant),
      ],
    );
  }
}

class _RecipeSummaryContent extends StatelessWidget {
  const _RecipeSummaryContent({
    required this.recipe,
    required this.seasonality,
    required this.monthName,
    required this.onEditRecipe,
  });

  final Recipe recipe;
  final RecipeSeasonality seasonality;
  final String monthName;
  final Future<void> Function() onEditRecipe;

  @override
  Widget build(BuildContext context) {
    final cookingModeTagsForRecipe = recipe.tags.where(
      cookingModeTags.contains,
    );

    final recipeTypeTagsForRecipe = recipe.tags.where(recipeTypeTags.contains);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CompactSummaryRow(
          icon: Icons.restaurant_menu,
          label: 'Cuisson',
          children: [
            if (cookingModeTagsForRecipe.isNotEmpty)
              for (final tag in cookingModeTagsForRecipe)
                _CompactSummaryChip(icon: Icons.check, label: tag)
            else
              _MissingSummaryChip(
                label: 'À compléter',
                onPressed: onEditRecipe,
              ),
          ],
        ),
        const SizedBox(height: 10),
        _CompactSummaryRow(
          icon: Icons.sell_outlined,
          label: 'Type',
          children: [
            if (recipeTypeTagsForRecipe.isNotEmpty)
              for (final tag in recipeTypeTagsForRecipe)
                _CompactSummaryChip(icon: Icons.check, label: tag)
            else
              _MissingSummaryChip(
                label: 'À compléter',
                onPressed: onEditRecipe,
              ),
          ],
        ),
        if ((recipe.sourceUrl ?? '').isNotEmpty) ...[
          const SizedBox(height: 10),
          _SourceUrlSummaryRow(sourceUrl: recipe.sourceUrl!),
        ],
      ],
    );
  }
}

class _SourceUrlSummaryRow extends StatelessWidget {
  const _SourceUrlSummaryRow({required this.sourceUrl});

  final String sourceUrl;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.link, size: 20, color: colorScheme.primary),
        const SizedBox(width: 8),
        const SizedBox(
          width: 78,
          child: Text('Source', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
        Expanded(
          child: SelectableText(
            sourceUrl,
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _CompactSummaryRow extends StatelessWidget {
  const _CompactSummaryRow({
    required this.icon,
    required this.label,
    required this.children,
  });

  final IconData icon;
  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: colorScheme.primary),
        const SizedBox(width: 8),
        SizedBox(
          width: 78,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        Expanded(child: Wrap(spacing: 6, runSpacing: 6, children: children)),
      ],
    );
  }
}

class _CompactSummaryChip extends StatelessWidget {
  const _CompactSummaryChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

class _MissingSummaryChip extends StatelessWidget {
  const _MissingSummaryChip({required this.label, required this.onPressed});

  final String label;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ActionChip(
      avatar: Icon(Icons.edit_outlined, size: 16, color: colorScheme.primary),
      label: Text(label),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onPressed: () async {
        await onPressed();
      },
    );
  }
}
