import 'package:flutter/material.dart';

import '../data/ingredient_categories.dart';
import '../data/ingredient_units.dart';
import '../data/recipe_ratings.dart';
import '../data/recipe_review_statuses.dart';
import '../data/recipe_tags.dart';
import '../models/ingredient.dart';
import '../models/recipe.dart';
import '../data/recipe_emojis.dart';
import '../services/preparation_step_analyzer.dart';

class RecipeFormScreen extends StatefulWidget {
  const RecipeFormScreen({super.key, this.initialRecipe, this.isDraft = false});

  final Recipe? initialRecipe;
  final bool isDraft;

  @override
  State<RecipeFormScreen> createState() => _RecipeFormScreenState();
}

class _RecipeFormScreenState extends State<RecipeFormScreen> {
  final formKey = GlobalKey<FormState>();

  final nameController = TextEditingController();
  final sourceUrlController = TextEditingController();
  final prepTimeController = TextEditingController();
  final cookTimeController = TextEditingController();
  final List<TextEditingController> stepControllers = [];

  final List<_IngredientControllers> ingredientRows = [];
  final Set<String> selectedTags = {};

  int? selectedRating;
  String selectedReviewStatus = defaultRecipeReviewStatus;
  String selectedEmoji = defaultRecipeEmoji;
  bool get isEditing => widget.initialRecipe != null && !widget.isDraft;
  @override
  void initState() {
    super.initState();

    final initialRecipe = widget.initialRecipe;

    if (initialRecipe != null) {
      nameController.text = initialRecipe.name;
      sourceUrlController.text = initialRecipe.sourceUrl ?? '';
      prepTimeController.text = initialRecipe.prepTimeMinutes?.toString() ?? '';
      cookTimeController.text = initialRecipe.cookTimeMinutes?.toString() ?? '';
      for (final step in splitPreparationSteps(initialRecipe.steps)) {
        stepControllers.add(TextEditingController(text: step));
      }
      selectedTags.addAll(initialRecipe.tags);

      selectedRating = recipeRatings.contains(initialRecipe.rating)
          ? initialRecipe.rating
          : null;

      selectedReviewStatus =
          recipeReviewStatuses.contains(initialRecipe.reviewStatus)
          ? initialRecipe.reviewStatus
          : defaultRecipeReviewStatus;

      selectedEmoji = recipeEmojiOptions.contains(initialRecipe.emoji)
          ? initialRecipe.emoji
          : defaultRecipeEmoji;
      for (final ingredient in initialRecipe.ingredients) {
        ingredientRows.add(_IngredientControllers.fromIngredient(ingredient));
      }
    }
    if (stepControllers.isEmpty) {
      stepControllers.add(TextEditingController());
    }
    if (ingredientRows.isEmpty) {
      ingredientRows.add(_IngredientControllers.empty());
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    sourceUrlController.dispose();
    prepTimeController.dispose();
    cookTimeController.dispose();
    for (final controller in stepControllers) {
      controller.dispose();
    }

    for (final row in ingredientRows) {
      row.dispose();
    }

    super.dispose();
  }

  void addIngredientRow() {
    setState(() {
      ingredientRows.add(_IngredientControllers.empty());
    });
  }

  void removeIngredientRow(int index) {
    if (ingredientRows.length == 1) {
      return;
    }

    setState(() {
      final removedRow = ingredientRows.removeAt(index);
      removedRow.dispose();
    });
  }

  void toggleTag(String tag, bool isSelected) {
    setState(() {
      if (isSelected) {
        selectedTags.add(tag);
      } else {
        selectedTags.remove(tag);
      }
    });
  }

  double? parseQuantity(String value) {
    final trimmedValue = value.trim();

    if (trimmedValue.isEmpty) {
      return null;
    }

    return double.tryParse(trimmedValue.replaceAll(',', '.'));
  }

  int? parseTime(String value) {
    final trimmedValue = value.trim();

    if (trimmedValue.isEmpty) {
      return null;
    }

    return int.tryParse(trimmedValue);
  }

  List<String> buildOrderedTags() {
    return recipeTags.where((tag) => selectedTags.contains(tag)).toList();
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

  List<String> buildPreparationSteps() {
    return stepControllers
        .map((controller) => controller.text.trim())
        .where((step) => step.isNotEmpty)
        .toList();
  }

  String buildPreparationText() {
    return buildPreparationSteps().join('\n\n');
  }

  void movePreparationStep(int oldIndex, int newIndex) {
    if (newIndex < 0 || newIndex >= stepControllers.length) {
      return;
    }

    setState(() {
      final controller = stepControllers.removeAt(oldIndex);
      stepControllers.insert(newIndex, controller);
    });
  }

  void addPreparationStep() {
    setState(() {
      stepControllers.add(TextEditingController());
    });
  }

  void removePreparationStep(int index) {
    if (stepControllers.length == 1) {
      return;
    }

    setState(() {
      final removedController = stepControllers.removeAt(index);
      removedController.dispose();
    });
  }

  List<String> getCurrentIngredientNames() {
    return ingredientRows
        .map((row) => row.nameController.text.trim())
        .where((name) => name.isNotEmpty)
        .toList();
  }

  Future<void> analyzePreparationSteps() async {
    final suggestions = PreparationStepAnalyzer.findImplicitPreparations(
      ingredientNames: getCurrentIngredientNames(),
      steps: buildPreparationSteps(),
    );

    if (suggestions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucune préparation implicite détectée.')),
      );
      return;
    }

    final shouldInsert = await showDialog<bool>(
      context: context,
      builder: (context) {
        return _PreparationAnalysisDialog(suggestions: suggestions);
      },
    );

    if (shouldInsert != true) {
      return;
    }

    final preparationStep = PreparationStepAnalyzer.buildPreparationStep(
      suggestions,
    );

    setState(() {
      stepControllers.insert(0, TextEditingController(text: preparationStep));
    });

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${suggestions.length} préparation(s) préalable(s) ajoutée(s).',
        ),
      ),
    );
  }

  void saveRecipe() {
    final isValid = formKey.currentState?.validate() ?? false;

    if (!isValid) {
      return;
    }

    final preparationSteps = buildPreparationSteps();

    if (preparationSteps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ajoute au moins une étape de préparation.'),
        ),
      );
      return;
    }

    final ingredients = ingredientRows
        .map((row) {
          return Ingredient(
            name: row.nameController.text.trim(),
            quantity: parseQuantity(row.quantityController.text),
            unit: row.unit,
            category: row.category,
            includeInShoppingList: row.includeInShoppingList,
          );
        })
        .where((ingredient) => ingredient.name.isNotEmpty)
        .toList();

    final recipe = Recipe(
      id: isEditing
          ? widget.initialRecipe!.id
          : DateTime.now().millisecondsSinceEpoch.toString(),
      name: nameController.text.trim(),
      ingredients: ingredients,
      steps: preparationSteps.join('\n\n'),
      tags: buildOrderedTags(),
      sourceUrl: sourceUrlController.text.trim().isEmpty
          ? null
          : sourceUrlController.text.trim(),
      prepTimeMinutes: parseTime(prepTimeController.text),
      cookTimeMinutes: parseTime(cookTimeController.text),
      rating: selectedRating,
      reviewStatus: selectedReviewStatus,
      emoji: selectedEmoji,
    );
    Navigator.of(context).pop(recipe);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Modifier la recette' : 'Ajouter une recette'),
        actions: [
          IconButton(
            tooltip: 'Enregistrer',
            onPressed: saveRecipe,
            icon: const Icon(Icons.save_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _FormHeader(isEditing: isEditing),
              const SizedBox(height: 16),
              _FormSectionCard(
                title: 'Informations',
                icon: Icons.restaurant_menu,
                child: Column(
                  children: [
                    TextFormField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Nom de la recette',
                        prefixIcon: Icon(Icons.restaurant),
                      ),
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Entre un nom de recette.';
                        }

                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: sourceUrlController,
                      decoration: const InputDecoration(
                        labelText: 'URL source',
                        hintText: 'https://...',
                        prefixIcon: Icon(Icons.link),
                      ),
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        final url = value?.trim() ?? '';

                        if (url.isEmpty) {
                          return null;
                        }

                        final uri = Uri.tryParse(url);

                        if (uri == null ||
                            !uri.hasScheme ||
                            !uri.hasAuthority) {
                          return 'Lien invalide';
                        }

                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: prepTimeController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Préparation',
                              hintText: 'Ex : 15',
                              suffixText: 'min',
                              prefixIcon: Icon(Icons.timer_outlined),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return null;
                              }

                              final duration = parseTime(value);

                              if (duration == null || duration <= 0) {
                                return 'Temps invalide';
                              }

                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: cookTimeController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Cuisson',
                              hintText: 'Ex : 30',
                              suffixText: 'min',
                              prefixIcon: Icon(
                                Icons.local_fire_department_outlined,
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return null;
                              }

                              final duration = parseTime(value);

                              if (duration == null || duration <= 0) {
                                return 'Temps invalide';
                              }

                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: selectedRating ?? 0,
                      decoration: const InputDecoration(
                        labelText: 'Note du plat',
                        prefixIcon: Icon(Icons.star_rate_outlined),
                      ),
                      items: [
                        const DropdownMenuItem<int>(
                          value: 0,
                          child: Text('Non noté'),
                        ),
                        for (final rating in recipeRatings)
                          DropdownMenuItem<int>(
                            value: rating,
                            child: Text('$rating/10'),
                          ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          selectedRating = value == 0 ? null : value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue:
                          recipeReviewStatuses.contains(selectedReviewStatus)
                          ? selectedReviewStatus
                          : defaultRecipeReviewStatus,
                      decoration: const InputDecoration(
                        labelText: 'Statut de vérification',
                        prefixIcon: Icon(Icons.fact_check_outlined),
                      ),
                      items: recipeReviewStatuses.map((status) {
                        return DropdownMenuItem(
                          value: status,
                          child: Text(status),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }

                        setState(() {
                          selectedReviewStatus = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
              _FormSectionCard(
                title: 'Emoji',
                icon: Icons.emoji_food_beverage_outlined,
                child: _RecipeEmojiSelector(
                  selectedEmoji: selectedEmoji,
                  onEmojiSelected: (emoji) {
                    setState(() {
                      selectedEmoji = emoji;
                    });
                  },
                ),
              ),
              _FormSectionCard(
                title: 'Tags',
                icon: Icons.sell_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Classe la recette selon son mode de préparation et son type.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 14),
                    for (final group in recipeTagGroups) ...[
                      Text(
                        group.label,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final tag in group.tags)
                            FilterChip(
                              label: Text(tag),
                              selected: selectedTags.contains(tag),
                              onSelected: (isSelected) {
                                toggleTag(tag, isSelected);
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                    ],
                  ],
                ),
              ),
              _FormSectionCard(
                title: 'Ingrédients',
                icon: Icons.shopping_basket_outlined,
                trailing: _SmallBadge(label: '${ingredientRows.length}'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (int index = 0; index < ingredientRows.length; index++)
                      _IngredientInputCard(
                        key: ValueKey(ingredientRows[index]),
                        index: index,
                        controllers: ingredientRows[index],
                        canDelete: ingredientRows.length > 1,
                        onDelete: () {
                          removeIngredientRow(index);
                        },
                        onCategoryChanged: (category) {
                          setState(() {
                            ingredientRows[index].category = category;
                          });
                        },
                        onUnitChanged: (unit) {
                          setState(() {
                            ingredientRows[index].unit = unit;
                          });
                        },
                        onIncludeInShoppingListChanged:
                            (includeInShoppingList) {
                              setState(() {
                                ingredientRows[index].includeInShoppingList =
                                    includeInShoppingList;
                              });
                            },
                        parseQuantity: parseQuantity,
                      ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: addIngredientRow,
                      icon: const Icon(Icons.add),
                      label: const Text('Ajouter un ingrédient'),
                    ),
                  ],
                ),
              ),
              _FormSectionCard(
                title: 'Préparation',
                icon: Icons.notes_outlined,
                trailing: _SmallBadge(label: '${stepControllers.length}'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Découpe la recette en étapes simples à suivre pendant la cuisine.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: analyzePreparationSteps,
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('Analyser la préparation'),
                    ),
                    const SizedBox(height: 12),
                    for (int index = 0; index < stepControllers.length; index++)
                      _PreparationStepInputCard(
                        key: ValueKey(stepControllers[index]),
                        index: index,
                        controller: stepControllers[index],
                        canDelete: stepControllers.length > 1,
                        canMoveUp: index > 0,
                        canMoveDown: index < stepControllers.length - 1,
                        onDelete: () {
                          removePreparationStep(index);
                        },
                        onMoveUp: () {
                          movePreparationStep(index, index - 1);
                        },
                        onMoveDown: () {
                          movePreparationStep(index, index + 1);
                        },
                      ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: addPreparationStep,
                      icon: const Icon(Icons.add),
                      label: const Text('Ajouter une étape'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: saveRecipe,
                icon: const Icon(Icons.save),
                label: Text(
                  isEditing
                      ? 'Enregistrer les modifications'
                      : 'Enregistrer la recette',
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _FormHeader extends StatelessWidget {
  const _FormHeader({required this.isEditing});

  final bool isEditing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              isEditing ? Icons.edit_outlined : Icons.add,
              color: colorScheme.primary,
              size: 30,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEditing ? 'Modifier une recette' : 'Nouvelle recette',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onPrimaryContainer,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  isEditing
                      ? 'Mets à jour les informations de ta recette.'
                      : 'Ajoute les infos principales, les ingrédients et la préparation.',
                  style: TextStyle(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreparationAnalysisDialog extends StatelessWidget {
  const _PreparationAnalysisDialog({required this.suggestions});

  final List<PreparationStepSuggestion> suggestions;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Préparations préalables'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Ces éléments semblent être utilisés déjà préparés. Tu peux ajouter une étape au début de la recette.',
            ),
            const SizedBox(height: 12),
            for (final suggestion in suggestions)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle_outline, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(suggestion.text)),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(false);
          },
          child: const Text('Ignorer'),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.of(context).pop(true);
          },
          icon: const Icon(Icons.add),
          label: const Text('Ajouter l’étape'),
        ),
      ],
    );
  }
}

class _FormSectionCard extends StatelessWidget {
  const _FormSectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: colorScheme.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                ?trailing,
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

class _RecipeEmojiSelector extends StatelessWidget {
  const _RecipeEmojiSelector({
    required this.selectedEmoji,
    required this.onEmojiSelected,
  });

  final String selectedEmoji;
  final ValueChanged<String> onEmojiSelected;

  Future<void> openEmojiPicker(BuildContext context) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Choisir un emoji',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choisis une icône qui représente bien ton plat.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              for (final category in recipeEmojiCategories) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  child: Text(
                    category.label,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final emoji in category.emojis)
                      _RecipeEmojiChoice(
                        emoji: emoji,
                        isSelected: emoji == selectedEmoji,
                        onTap: () {
                          Navigator.of(context).pop(emoji);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        );
      },
    );

    if (selected == null) {
      return;
    }

    onEmojiSelected(selected);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Text(selectedEmoji, style: const TextStyle(fontSize: 34)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Emoji du plat',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'Il sera affiché dans les recettes, le détail et le planning.',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  await openEmojiPicker(context);
                },
                icon: const Icon(Icons.emoji_food_beverage_outlined),
                label: const Text('Choisir un emoji'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecipeEmojiChoice extends StatelessWidget {
  const _RecipeEmojiChoice({
    required this.emoji,
    required this.isSelected,
    required this.onTap,
  });

  final String emoji;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        width: 54,
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primaryContainer
              : colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 26)),
      ),
    );
  }
}

class _PreparationStepInputCard extends StatelessWidget {
  const _PreparationStepInputCard({
    super.key,
    required this.index,
    required this.controller,
    required this.canDelete,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onDelete,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final int index;
  final TextEditingController controller;
  final bool canDelete;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onDelete;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Row(
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
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Étape ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: 'Monter cette étape',
                onPressed: canMoveUp ? onMoveUp : null,
                icon: const Icon(Icons.arrow_upward),
              ),
              IconButton(
                tooltip: 'Descendre cette étape',
                onPressed: canMoveDown ? onMoveDown : null,
                icon: const Icon(Icons.arrow_downward),
              ),
              IconButton(
                tooltip: 'Supprimer cette étape',
                onPressed: canDelete ? onDelete : null,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: controller,
            minLines: 2,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: 'Description',
              hintText: 'Ex : Faire revenir les oignons à feu moyen.',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _IngredientInputCard extends StatelessWidget {
  const _IngredientInputCard({
    super.key,
    required this.index,
    required this.controllers,
    required this.canDelete,
    required this.onDelete,
    required this.onCategoryChanged,
    required this.onUnitChanged,
    required this.onIncludeInShoppingListChanged,
    required this.parseQuantity,
  });

  final int index;
  final _IngredientControllers controllers;
  final bool canDelete;
  final VoidCallback onDelete;
  final ValueChanged<String> onCategoryChanged;
  final ValueChanged<String> onUnitChanged;
  final double? Function(String value) parseQuantity;
  final ValueChanged<bool> onIncludeInShoppingListChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _SmallBadge(label: '#${index + 1}'),
              const Spacer(),
              IconButton(
                tooltip: 'Supprimer cet ingrédient',
                onPressed: canDelete ? onDelete : null,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: controllers.nameController,
            decoration: const InputDecoration(
              labelText: 'Nom',
              hintText: 'Ex : pâtes',
              prefixIcon: Icon(Icons.egg_alt_outlined),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Entre le nom de l’ingrédient.';
              }

              return null;
            },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: ingredientCategories.contains(controllers.category)
                ? controllers.category
                : defaultIngredientCategory,
            decoration: const InputDecoration(
              labelText: 'Catégorie',
              prefixIcon: Icon(Icons.category_outlined),
            ),
            items: ingredientCategories.map((category) {
              return DropdownMenuItem(value: category, child: Text(category));
            }).toList(),
            onChanged: (value) {
              if (value == null) {
                return;
              }

              onCategoryChanged(value);
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: controllers.quantityController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Quantité',
                    hintText: 'Ex : 250',
                    prefixIcon: Icon(Icons.scale_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return null;
                    }

                    if (parseQuantity(value) == null) {
                      return 'Nombre invalide';
                    }

                    return null;
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: ingredientUnits.contains(controllers.unit)
                      ? controllers.unit
                      : noIngredientUnit,
                  decoration: const InputDecoration(
                    labelText: 'Unité',
                    prefixIcon: Icon(Icons.straighten),
                  ),
                  items: ingredientUnits.map((unit) {
                    return DropdownMenuItem(
                      value: unit,
                      child: Text(getIngredientUnitLabel(unit)),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }

                    onUnitChanged(value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: controllers.includeInShoppingList,
            onChanged: onIncludeInShoppingListChanged,
            title: const Text(
              'Ajouter à la liste de courses',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              controllers.includeInShoppingList
                  ? 'Cet ingrédient sera ajouté aux courses.'
                  : 'Cet ingrédient restera dans la recette, mais pas dans les courses.',
            ),
            secondary: Icon(
              controllers.includeInShoppingList
                  ? Icons.shopping_cart_outlined
                  : Icons.remove_shopping_cart_outlined,
            ),
          ),
        ],
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

class _IngredientControllers {
  _IngredientControllers({
    required this.nameController,
    required this.quantityController,
    required this.unit,
    required this.category,
    required this.includeInShoppingList,
  });

  factory _IngredientControllers.empty() {
    return _IngredientControllers(
      nameController: TextEditingController(),
      quantityController: TextEditingController(),
      unit: noIngredientUnit,
      category: defaultIngredientCategory,
      includeInShoppingList: true,
    );
  }

  factory _IngredientControllers.fromIngredient(Ingredient ingredient) {
    return _IngredientControllers(
      nameController: TextEditingController(text: ingredient.name),
      quantityController: TextEditingController(
        text: ingredient.quantity == null ? '' : ingredient.formattedQuantity,
      ),
      unit: ingredientUnits.contains(ingredient.unit)
          ? ingredient.unit
          : noIngredientUnit,
      category: ingredient.category,
      includeInShoppingList: ingredient.includeInShoppingList,
    );
  }

  final TextEditingController nameController;
  final TextEditingController quantityController;

  String unit;
  String category;
  bool includeInShoppingList;

  void dispose() {
    nameController.dispose();
    quantityController.dispose();
  }
}
