import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../data/ingredient_categories.dart';
import '../data/pantry_ingredients.dart';
import '../models/ingredient.dart';
import '../models/recipe.dart';
import '../services/unit_converter.dart';
import '../data/planning_entries.dart';

class ShoppingListScreen extends StatefulWidget {
  const ShoppingListScreen({
    super.key,
    required this.recipes,
    required this.weeklyPlanning,
    required this.checkedShoppingItems,
    required this.onToggleItem,
    required this.onGoToPlanning,
    required this.onEditRecipe,
    required this.ingredientCategoryUpdateCount,
    required this.onUpdateIngredientCategories,
    required this.pantryIngredientNames,
    required this.onUpdatePantryIngredientNames,
  });

  final List<Recipe> recipes;
  final Map<String, String> weeklyPlanning;
  final Set<String> checkedShoppingItems;
  final Future<void> Function(String ingredient, bool isChecked) onToggleItem;
  final VoidCallback onGoToPlanning;
  final Future<void> Function(Recipe recipe) onEditRecipe;
  final int ingredientCategoryUpdateCount;
  final Future<void> Function() onUpdateIngredientCategories;
  final List<String> pantryIngredientNames;
  final Future<void> Function(Iterable<String> pantryIngredientNames)
  onUpdatePantryIngredientNames;

  @override
  State<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends State<ShoppingListScreen> {
  bool showOnlyItemsToCheck = false;
  bool showOnlyCategoryConflicts = false;
  bool isStoreModeEnabled = false;
  bool hideCheckedItems = false;

  Recipe? getRecipeById(String recipeId) {
    for (final recipe in widget.recipes) {
      if (recipe.id == recipeId) {
        return recipe;
      }
    }

    return null;
  }

  Map<String, ShoppingItem> buildShoppingItems() {
    final Map<String, ShoppingItem> shoppingItems = {};

    for (final planningValue in widget.weeklyPlanning.values) {
      for (final recipeId in getRecipeIdsFromPlanningValue(planningValue)) {
        final recipe = getRecipeById(recipeId);

        if (recipe == null) {
          continue;
        }

        for (final ingredient in recipe.ingredients) {
          if (!ingredient.includeInShoppingList) {
            continue;
          }

          if (shouldExcludeFromShoppingList(
            ingredientName: ingredient.name,
            pantryIngredientNames: widget.pantryIngredientNames,
          )) {
            continue;
          }

          final normalizedName = ingredient.name.trim();
          final groupingName = normalizeIngredientNameForGrouping(
            normalizedName,
          );

          if (groupingName.isEmpty) {
            continue;
          }

          final normalizedCategory = ingredient.category.trim().isEmpty
              ? defaultIngredientCategory
              : ingredient.category.trim();

          final normalizedUnit = UnitConverter.normalize(ingredient.unit);

          final key =
              '${normalizeIngredientNameForGrouping(normalizedCategory)}|'
              '$groupingName|'
              '${normalizedUnit.groupKey}';

          final existingItem = shoppingItems[key];

          if (existingItem == null) {
            shoppingItems[key] = ShoppingItem.fromIngredient(
              key: key,
              groupingName: groupingName,
              ingredient: ingredient,
              recipe: recipe,
              category: normalizedCategory,
              normalizedUnit: normalizedUnit,
            );
          } else {
            existingItem.addIngredient(ingredient, recipe);
          }
        }
      }
    }

    markCategoryConflicts(shoppingItems.values);

    final sortedEntries = shoppingItems.entries.toList()
      ..sort((a, b) {
        final categoryComparison = getIngredientCategoryOrder(
          a.value.category,
        ).compareTo(getIngredientCategoryOrder(b.value.category));

        if (categoryComparison != 0) {
          return categoryComparison;
        }

        return a.value.name.toLowerCase().compareTo(b.value.name.toLowerCase());
      });

    return Map.fromEntries(sortedEntries);
  }

  void markCategoryConflicts(Iterable<ShoppingItem> items) {
    final categoriesByIngredient = <String, Set<String>>{};

    for (final item in items) {
      categoriesByIngredient
          .putIfAbsent(item.groupingName, () => <String>{})
          .add(item.category);
    }

    for (final item in items) {
      final categories = categoriesByIngredient[item.groupingName] ?? {};
      item.categoryConflictCategories = categories.length > 1
          ? categories.toSet()
          : <String>{};
    }
  }

  Map<String, List<ShoppingItem>> groupItemsByCategory(
    Map<String, ShoppingItem> shoppingItems,
  ) {
    final groupedItems = <String, List<ShoppingItem>>{};

    for (final item in shoppingItems.values) {
      groupedItems.putIfAbsent(item.category, () => []);
      groupedItems[item.category]!.add(item);
    }

    return groupedItems;
  }

  List<String> getOrderedCategories(
    Map<String, List<ShoppingItem>> groupedItems,
  ) {
    final knownCategories = ingredientCategories.where(
      groupedItems.containsKey,
    );

    final unknownCategories = groupedItems.keys.where(
      (category) => !ingredientCategories.contains(category),
    );

    return [...knownCategories, ...unknownCategories];
  }

  int getSelectedMealsCount() {
    return widget.weeklyPlanning.length;
  }

  String normalizeIngredientNameForGrouping(String value) {
    final buffer = StringBuffer();

    for (final rune in value.toLowerCase().trim().runes) {
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
        case 0x2019:
        case 0x0027:
          buffer.write(' ');
        default:
          buffer.writeCharCode(rune);
      }
    }

    final normalized = buffer
        .toString()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .split(' ')
        .map(normalizeIngredientWordForGrouping)
        .where((word) => word.isNotEmpty)
        .join(' ');

    return normalized;
  }

  String normalizeIngredientWordForGrouping(String word) {
    if (word.length <= 3) {
      return word;
    }

    const invariantWords = {
      'mais',
      'pois',
      'noix',
      'riz',
      'jus',
      'lait',
      'sel',
      'ail',
    };

    if (invariantWords.contains(word)) {
      return word;
    }

    if (word.endsWith('aux') && word.length > 4) {
      return '${word.substring(0, word.length - 3)}al';
    }

    if (word.endsWith('s') || word.endsWith('x')) {
      return word.substring(0, word.length - 1);
    }

    return word;
  }

  String buildShareText(Map<String, List<ShoppingItem>> groupedItems) {
    final buffer = StringBuffer();

    buffer.writeln('Liste de courses de la semaine');
    buffer.writeln();

    for (final category in getOrderedCategories(groupedItems)) {
      final items = groupedItems[category];

      if (items == null || items.isEmpty) {
        continue;
      }

      buffer.writeln(category);

      for (final item in items) {
        buffer.writeln('- ${item.displayText}');
      }

      buffer.writeln();
    }

    return buffer.toString().trim();
  }

  Future<void> shareShoppingList(
    BuildContext context,
    Map<String, List<ShoppingItem>> groupedItems,
  ) async {
    final shareText = buildShareText(groupedItems);

    if (shareText.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La liste de courses est vide.')),
      );
      return;
    }

    await SharePlus.instance.share(
      ShareParams(text: shareText, subject: 'Liste de courses'),
    );
  }

  void showShoppingItemDetails(BuildContext context, ShoppingItem item) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return _ShoppingItemDetailsSheet(
          item: item,
          onEditRecipe: (recipeId) {
            final recipe = getRecipeById(recipeId);

            if (recipe == null) {
              return;
            }

            Navigator.of(context).pop();
            widget.onEditRecipe(recipe);
          },
        );
      },
    );
  }

  void showPantryIngredientsSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return _PantryIngredientsSheet(
          pantryIngredientNames: widget.pantryIngredientNames,
          onSave: widget.onUpdatePantryIngredientNames,
        );
      },
    );
  }

  IconData getCategoryIcon(String category) {
    switch (category) {
      case 'Fruits & légumes':
        return Icons.eco_outlined;
      case 'Frais':
        return Icons.kitchen_outlined;
      case 'Épicerie':
        return Icons.local_grocery_store_outlined;
      case 'Viandes / poissons':
        return Icons.set_meal_outlined;
      case 'Surgelés':
        return Icons.ac_unit_outlined;
      case 'Boissons':
        return Icons.local_drink_outlined;
      case 'Hygiène / entretien':
        return Icons.cleaning_services_outlined;
      default:
        return Icons.shopping_basket_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final shoppingItems = buildShoppingItems();
    final itemsToCheckCount = shoppingItems.values
        .where((item) => item.hasUnquantifiedIngredient)
        .length;
    final categoryConflictCount = shoppingItems.values
        .where((item) => item.hasCategoryConflict)
        .map((item) => item.groupingName)
        .toSet()
        .length;
    var displayedEntries = shoppingItems.entries;

    if (showOnlyItemsToCheck) {
      displayedEntries = displayedEntries.where(
        (entry) => entry.value.hasUnquantifiedIngredient,
      );
    }

    if (showOnlyCategoryConflicts) {
      displayedEntries = displayedEntries.where(
        (entry) => entry.value.hasCategoryConflict,
      );
    }

    final displayedShoppingItems = Map.fromEntries(displayedEntries);
    final visibleShoppingItems = hideCheckedItems
        ? Map.fromEntries(
            displayedShoppingItems.entries.where(
              (entry) => !widget.checkedShoppingItems.contains(entry.key),
            ),
          )
        : displayedShoppingItems;
    final groupedItems = groupItemsByCategory(visibleShoppingItems);
    final orderedCategories = getOrderedCategories(groupedItems);
    final selectedMealsCount = getSelectedMealsCount();

    if (widget.weeklyPlanning.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: _EmptyShoppingCard(
          title: 'Ton planning est vide',
          message:
              'Ajoute des recettes dans le planning pour générer automatiquement ta liste de courses.',
          buttonLabel: 'Remplir le planning',
          icon: Icons.shopping_basket_outlined,
          onPressed: widget.onGoToPlanning,
        ),
      );
    }

    if (shoppingItems.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: _EmptyShoppingCard(
          title: 'Aucun ingrédient',
          message: 'Les recettes choisies ne contiennent aucun ingrédient.',
          buttonLabel: '',
          icon: Icons.shopping_basket_outlined,
          onPressed: null,
        ),
      );
    }

    final checkedCount = displayedShoppingItems.keys
        .where((key) => widget.checkedShoppingItems.contains(key))
        .length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ShoppingHeader(
          selectedMealsCount: selectedMealsCount,
          checkedCount: checkedCount,
          totalCount: displayedShoppingItems.length,
          visibleCount: visibleShoppingItems.length,
          onShare: () async {
            await shareShoppingList(context, groupedItems);
          },
          itemsToCheckCount: itemsToCheckCount,
          categoryConflictCount: categoryConflictCount,
          showOnlyItemsToCheck: showOnlyItemsToCheck,
          showOnlyCategoryConflicts: showOnlyCategoryConflicts,
          isStoreModeEnabled: isStoreModeEnabled,
          hideCheckedItems: hideCheckedItems,
          ingredientCategoryUpdateCount: widget.ingredientCategoryUpdateCount,
          pantryIngredientCount: widget.pantryIngredientNames.length,
          onToggleItemsToCheckFilter: itemsToCheckCount == 0
              ? null
              : () {
                  setState(() {
                    showOnlyItemsToCheck = !showOnlyItemsToCheck;
                  });
                },
          onToggleCategoryConflictFilter: categoryConflictCount == 0
              ? null
              : () {
                  setState(() {
                    showOnlyCategoryConflicts = !showOnlyCategoryConflicts;
                  });
                },
          onToggleStoreMode: () {
            setState(() {
              isStoreModeEnabled = !isStoreModeEnabled;

              if (!isStoreModeEnabled) {
                hideCheckedItems = false;
              }
            });
          },
          onToggleHideCheckedItems: isStoreModeEnabled
              ? () {
                  setState(() {
                    hideCheckedItems = !hideCheckedItems;
                  });
                }
              : null,
          onUpdateIngredientCategories:
              widget.ingredientCategoryUpdateCount == 0
              ? null
              : widget.onUpdateIngredientCategories,
          onEditPantryIngredients: () {
            showPantryIngredientsSheet(context);
          },
        ),
        const SizedBox(height: 16),
        if (visibleShoppingItems.isEmpty)
          _FilteredShoppingEmptyCard(
            message: showOnlyCategoryConflicts
                ? 'Aucune incohérence de catégorie à vérifier.'
                : 'Aucune quantité à vérifier.',
          )
        else
          for (final category in orderedCategories)
            _CategoryShoppingCard(
              category: category,
              icon: getCategoryIcon(category),
              items: groupedItems[category] ?? [],
              checkedShoppingItems: widget.checkedShoppingItems,
              isStoreModeEnabled: isStoreModeEnabled,
              onToggleItem: widget.onToggleItem,
              onShowItemDetails: (item) {
                showShoppingItemDetails(context, item);
              },
            ),
      ],
    );
  }
}

class _ShoppingHeader extends StatelessWidget {
  const _ShoppingHeader({
    required this.selectedMealsCount,
    required this.checkedCount,
    required this.totalCount,
    required this.visibleCount,
    required this.onShare,
    required this.itemsToCheckCount,
    required this.categoryConflictCount,
    required this.showOnlyItemsToCheck,
    required this.showOnlyCategoryConflicts,
    required this.isStoreModeEnabled,
    required this.hideCheckedItems,
    required this.ingredientCategoryUpdateCount,
    required this.pantryIngredientCount,
    required this.onToggleItemsToCheckFilter,
    required this.onToggleCategoryConflictFilter,
    required this.onToggleStoreMode,
    required this.onToggleHideCheckedItems,
    required this.onUpdateIngredientCategories,
    required this.onEditPantryIngredients,
  });

  final int selectedMealsCount;
  final int checkedCount;
  final int totalCount;
  final int visibleCount;
  final Future<void> Function() onShare;
  final int itemsToCheckCount;
  final int categoryConflictCount;
  final bool showOnlyItemsToCheck;
  final bool showOnlyCategoryConflicts;
  final bool isStoreModeEnabled;
  final bool hideCheckedItems;
  final int ingredientCategoryUpdateCount;
  final int pantryIngredientCount;
  final VoidCallback? onToggleItemsToCheckFilter;
  final VoidCallback? onToggleCategoryConflictFilter;
  final VoidCallback onToggleStoreMode;
  final VoidCallback? onToggleHideCheckedItems;
  final Future<void> Function()? onUpdateIngredientCategories;
  final VoidCallback onEditPantryIngredients;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final progress = totalCount == 0 ? 0.0 : checkedCount / totalCount;
    final isCompact = isStoreModeEnabled;

    return Container(
      padding: EdgeInsets.all(isCompact ? 14 : 20),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                isStoreModeEnabled
                    ? Icons.storefront_outlined
                    : Icons.shopping_cart_outlined,
                size: isCompact ? 28 : 36,
                color: colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isStoreModeEnabled
                      ? 'Courses en magasin'
                      : 'Liste de courses',
                  style: TextStyle(
                    fontSize: isCompact ? 22 : 28,
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onPrimaryContainer,
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: isCompact ? 6 : 8),
          Text(
            '$selectedMealsCount repas planifié(s) - '
            '$checkedCount/$totalCount article(s) acheté(s)'
            '${hideCheckedItems ? ' - $visibleCount restant(s)' : ''}',
            style: TextStyle(
              color: colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: isCompact ? 10 : 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: colorScheme.surface.withValues(alpha: 0.55),
            ),
          ),
          SizedBox(height: isCompact ? 12 : 16),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: onShare,
                  icon: const Icon(Icons.share),
                  label: const Text('Partager'),
                ),
                ActionChip(
                  onPressed: onEditPantryIngredients,
                  avatar: const Icon(Icons.inventory_2_outlined, size: 18),
                  label: Text('Stock maison ($pantryIngredientCount)'),
                ),
                if (itemsToCheckCount > 0)
                  FilterChip(
                    selected: showOnlyItemsToCheck,
                    onSelected: onToggleItemsToCheckFilter == null
                        ? null
                        : (_) {
                            onToggleItemsToCheckFilter!();
                          },
                    avatar: const Icon(Icons.error_outline, size: 18),
                    label: Text('$itemsToCheckCount à vérifier'),
                  ),
                if (categoryConflictCount > 0)
                  FilterChip(
                    selected: showOnlyCategoryConflicts,
                    onSelected: onToggleCategoryConflictFilter == null
                        ? null
                        : (_) {
                            onToggleCategoryConflictFilter!();
                          },
                    avatar: const Icon(Icons.category_outlined, size: 18),
                    label: Text(
                      '$categoryConflictCount catégorie(s) à vérifier',
                    ),
                  ),
                if (ingredientCategoryUpdateCount > 0)
                  ActionChip(
                    onPressed: onUpdateIngredientCategories == null
                        ? null
                        : () {
                            onUpdateIngredientCategories!();
                          },
                    avatar: const Icon(Icons.auto_fix_high_outlined, size: 18),
                    label: Text(
                      'Reclasser $ingredientCategoryUpdateCount ingrédient(s)',
                    ),
                  ),
                FilterChip(
                  selected: isStoreModeEnabled,
                  onSelected: (_) {
                    onToggleStoreMode();
                  },
                  avatar: const Icon(Icons.storefront_outlined, size: 18),
                  label: const Text('Mode magasin'),
                ),
                if (isStoreModeEnabled)
                  FilterChip(
                    selected: hideCheckedItems,
                    onSelected: onToggleHideCheckedItems == null
                        ? null
                        : (_) {
                            onToggleHideCheckedItems!();
                          },
                    avatar: const Icon(Icons.visibility_off_outlined, size: 18),
                    label: const Text('Masquer achetés'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryShoppingCard extends StatelessWidget {
  const _CategoryShoppingCard({
    required this.category,
    required this.icon,
    required this.items,
    required this.checkedShoppingItems,
    required this.isStoreModeEnabled,
    required this.onToggleItem,
    required this.onShowItemDetails,
  });

  final String category;
  final IconData icon;
  final List<ShoppingItem> items;
  final Set<String> checkedShoppingItems;
  final bool isStoreModeEnabled;
  final Future<void> Function(String ingredient, bool isChecked) onToggleItem;
  final void Function(ShoppingItem item) onShowItemDetails;

  @override
  Widget build(BuildContext context) {
    final checkedCount = items
        .where((item) => checkedShoppingItems.contains(item.key))
        .length;
    final displayedItems = [...items];

    if (isStoreModeEnabled) {
      displayedItems.sort((a, b) {
        final aChecked = checkedShoppingItems.contains(a.key);
        final bChecked = checkedShoppingItems.contains(b.key);

        if (aChecked != bChecked) {
          return aChecked ? 1 : -1;
        }

        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CategoryHeader(
              category: category,
              icon: icon,
              checkedCount: checkedCount,
              totalCount: items.length,
            ),
            const SizedBox(height: 10),
            for (final item in displayedItems)
              _ShoppingItemTile(
                item: item,
                isChecked: checkedShoppingItems.contains(item.key),
                isStoreModeEnabled: isStoreModeEnabled,
                onChanged: (value) async {
                  await onToggleItem(item.key, value);
                },
                onShowDetails: () {
                  onShowItemDetails(item);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({
    required this.category,
    required this.icon,
    required this.checkedCount,
    required this.totalCount,
  });

  final String category;
  final IconData icon;
  final int checkedCount;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            category,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
        ),
        _SmallBadge(label: '$checkedCount/$totalCount'),
      ],
    );
  }
}

class _ShoppingItemTile extends StatelessWidget {
  const _ShoppingItemTile({
    required this.item,
    required this.isChecked,
    required this.isStoreModeEnabled,
    required this.onChanged,
    required this.onShowDetails,
  });

  final ShoppingItem item;
  final bool isChecked;
  final bool isStoreModeEnabled;
  final Future<void> Function(bool value) onChanged;
  final VoidCallback onShowDetails;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDimmed = isStoreModeEnabled && isChecked;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isChecked
            ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.6)
            : colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            await onChanged(!isChecked);
          },
          onLongPress: onShowDetails,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 8,
              vertical: isStoreModeEnabled ? 4 : 6,
            ),
            child: Row(
              children: [
                Checkbox(
                  value: isChecked,
                  onChanged: (value) async {
                    await onChanged(value ?? false);
                  },
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    item.displayText,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      decoration: isChecked ? TextDecoration.lineThrough : null,
                      color: isChecked
                          ? colorScheme.onSurfaceVariant
                          : colorScheme.onSurface,
                      fontSize: isDimmed ? 13 : null,
                    ),
                  ),
                ),
                if (item.occurrences > 1)
                  _SmallBadge(label: '${item.occurrences} repas'),
                if (item.hasUnquantifiedIngredient) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'Quantité à vérifier',
                    child: Icon(
                      Icons.error_outline,
                      color: colorScheme.tertiary,
                    ),
                  ),
                ],
                if (item.hasCategoryConflict) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'Catégorie à vérifier',
                    child: Icon(
                      Icons.category_outlined,
                      color: colorScheme.error,
                    ),
                  ),
                ],
                IconButton(
                  tooltip: 'Voir les recettes',
                  onPressed: onShowDetails,
                  icon: const Icon(Icons.info_outline),
                  visualDensity: VisualDensity.compact,
                  iconSize: isStoreModeEnabled ? 20 : 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SmallBadge extends StatelessWidget {
  const _SmallBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colorScheme.primary,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _ShoppingItemDetailsSheet extends StatelessWidget {
  const _ShoppingItemDetailsSheet({
    required this.item,
    required this.onEditRecipe,
  });

  final ShoppingItem item;
  final void Function(String recipeId) onEditRecipe;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        shrinkWrap: true,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  item.hasUnquantifiedIngredient
                      ? Icons.error_outline
                      : item.hasCategoryConflict
                      ? Icons.category_outlined
                      : Icons.shopping_basket_outlined,
                  color: item.hasUnquantifiedIngredient
                      ? colorScheme.tertiary
                      : item.hasCategoryConflict
                      ? colorScheme.error
                      : colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.displayText,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      item.category,
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (item.hasUnquantifiedIngredient) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: colorScheme.onTertiaryContainer,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Une ou plusieurs recettes ne précisent pas la quantité.',
                      style: TextStyle(
                        color: colorScheme.onTertiaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (item.hasCategoryConflict) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.category_outlined,
                    color: colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Même ingrédient trouvé dans plusieurs catégories : '
                      '${item.sortedCategoryConflictCategories.join(', ')}.',
                      style: TextStyle(
                        color: colorScheme.onErrorContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          Text(
            'Utilisé dans',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          for (final source in item.sources)
            Card(
              child: ListTile(
                leading: CircleAvatar(child: Text(source.recipeEmoji)),
                title: Text(source.recipeName),
                subtitle: Text(
                  item.hasCategoryConflict
                      ? '${source.ingredientText} - ${source.category}'
                      : source.ingredientText,
                ),
                onTap: () {
                  onEditRecipe(source.recipeId);
                },
                trailing: source.hasQuantity
                    ? const Icon(Icons.edit_outlined)
                    : Tooltip(
                        message: 'Quantité non précisée',
                        child: Icon(
                          Icons.error_outline,
                          color: colorScheme.tertiary,
                        ),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PantryIngredientsSheet extends StatefulWidget {
  const _PantryIngredientsSheet({
    required this.pantryIngredientNames,
    required this.onSave,
  });

  final List<String> pantryIngredientNames;
  final Future<void> Function(Iterable<String> pantryIngredientNames) onSave;

  @override
  State<_PantryIngredientsSheet> createState() =>
      _PantryIngredientsSheetState();
}

class _PantryIngredientsSheetState extends State<_PantryIngredientsSheet> {
  late final TextEditingController ingredientController;
  late List<String> pantryIngredientNames;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    ingredientController = TextEditingController();
    pantryIngredientNames = normalizePantryIngredientNames(
      widget.pantryIngredientNames,
    );
  }

  @override
  void dispose() {
    ingredientController.dispose();
    super.dispose();
  }

  void addIngredient() {
    final name = ingredientController.text.trim();

    if (name.isEmpty) {
      return;
    }

    setState(() {
      pantryIngredientNames = normalizePantryIngredientNames([
        ...pantryIngredientNames,
        name,
      ]);
      ingredientController.clear();
    });
  }

  Future<void> save() async {
    setState(() {
      isSaving = true;
    });

    await widget.onSave(pantryIngredientNames);

    if (!mounted) {
      return;
    }

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(
              'Stock maison',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Ces ingrédients restent dans les recettes, mais ne sont pas ajoutés aux courses.',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: ingredientController,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Ajouter un ingrédient',
                      hintText: 'Ex : moutarde',
                      prefixIcon: Icon(Icons.inventory_2_outlined),
                    ),
                    onSubmitted: (_) {
                      addIngredient();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Ajouter',
                  onPressed: addIngredient,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (pantryIngredientNames.isEmpty)
              const Text('Aucun ingrédient dans le stock maison.')
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final ingredientName in pantryIngredientNames)
                    InputChip(
                      label: Text(ingredientName),
                      onDeleted: () {
                        setState(() {
                          pantryIngredientNames = [
                            for (final name in pantryIngredientNames)
                              if (name != ingredientName) name,
                          ];
                        });
                      },
                    ),
                ],
              ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: isSaving ? null : save,
              icon: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilteredShoppingEmptyCard extends StatelessWidget {
  const _FilteredShoppingEmptyCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline, color: colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyShoppingCard extends StatelessWidget {
  const _EmptyShoppingCard({
    required this.title,
    required this.message,
    required this.buttonLabel,
    required this.icon,
    required this.onPressed,
  });

  final String title;
  final String message;
  final String buttonLabel;
  final IconData icon;
  final VoidCallback? onPressed;

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
              child: Icon(icon, size: 38, color: colorScheme.primary),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            if (onPressed != null && buttonLabel.isNotEmpty) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onPressed,
                icon: const Icon(Icons.calendar_month_outlined),
                label: Text(buttonLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ShoppingItem {
  ShoppingItem({
    required this.key,
    required this.groupingName,
    required this.name,
    required this.category,
    required this.normalizedUnit,
    required this.baseQuantity,
    required this.occurrences,
    required this.hasUnquantifiedIngredient,
    required this.sources,
  });

  factory ShoppingItem.fromIngredient({
    required String key,
    required String groupingName,
    required Ingredient ingredient,
    required Recipe recipe,
    required String category,
    required NormalizedUnit normalizedUnit,
  }) {
    return ShoppingItem(
      key: key,
      groupingName: groupingName,
      name: ingredient.name.trim(),
      category: category,
      normalizedUnit: normalizedUnit,
      baseQuantity: ingredient.quantity == null
          ? null
          : normalizedUnit.convertToBase(ingredient.quantity!),
      occurrences: 1,
      hasUnquantifiedIngredient: ingredient.quantity == null,
      sources: [
        ShoppingItemSource.fromIngredient(
          ingredient: ingredient,
          recipe: recipe,
        ),
      ],
    );
  }

  final String key;
  final String groupingName;
  final String name;
  final String category;
  final NormalizedUnit normalizedUnit;

  double? baseQuantity;
  int occurrences;
  bool hasUnquantifiedIngredient;
  Set<String> categoryConflictCategories = {};
  final List<ShoppingItemSource> sources;

  bool get hasCategoryConflict => categoryConflictCategories.length > 1;

  List<String> get sortedCategoryConflictCategories {
    return categoryConflictCategories.toList()..sort((a, b) {
      final categoryComparison = getIngredientCategoryOrder(
        a,
      ).compareTo(getIngredientCategoryOrder(b));

      if (categoryComparison != 0) {
        return categoryComparison;
      }

      return a.toLowerCase().compareTo(b.toLowerCase());
    });
  }

  void addIngredient(Ingredient ingredient, Recipe recipe) {
    occurrences++;
    sources.add(
      ShoppingItemSource.fromIngredient(ingredient: ingredient, recipe: recipe),
    );

    if (ingredient.quantity == null) {
      hasUnquantifiedIngredient = true;
      return;
    }

    final ingredientUnit = UnitConverter.normalize(ingredient.unit);
    final convertedQuantity = ingredientUnit.convertToBase(
      ingredient.quantity!,
    );

    baseQuantity = (baseQuantity ?? 0) + convertedQuantity;
  }

  String get displayText {
    final quantity = baseQuantity;

    if (quantity == null) {
      return name;
    }

    final quantityText = UnitConverter.formatBaseQuantity(
      normalizedUnit,
      quantity,
    );

    final text = '$quantityText $name';

    if (hasUnquantifiedIngredient) {
      return '$text + quantité non précisée';
    }

    return text;
  }
}

class ShoppingItemSource {
  const ShoppingItemSource({
    required this.recipeId,
    required this.recipeName,
    required this.recipeEmoji,
    required this.ingredientText,
    required this.category,
    required this.hasQuantity,
  });

  factory ShoppingItemSource.fromIngredient({
    required Ingredient ingredient,
    required Recipe recipe,
  }) {
    return ShoppingItemSource(
      recipeId: recipe.id,
      recipeName: recipe.name,
      recipeEmoji: recipe.emoji,
      ingredientText: ingredient.displayText,
      category: ingredient.category.trim().isEmpty
          ? defaultIngredientCategory
          : ingredient.category.trim(),
      hasQuantity: ingredient.quantity != null,
    );
  }

  final String recipeId;
  final String recipeName;
  final String recipeEmoji;
  final String ingredientText;
  final String category;
  final bool hasQuantity;
}
