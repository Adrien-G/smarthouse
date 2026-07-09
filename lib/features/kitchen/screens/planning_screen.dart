import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../data/planning_entries.dart';
import '../data/meal_slots.dart';
import '../models/meal_history_entry.dart';
import '../models/recipe.dart';
import 'cooking_screen.dart';

class _AutoFillOptions {
  const _AutoFillOptions({required this.isVacationMode});

  final bool isVacationMode;
}

class PlanningScreen extends StatelessWidget {
  const PlanningScreen({
    super.key,
    required this.recipes,
    required this.weeklyPlanning,
    required this.onSelectRecipe,
    required this.onSetSpecialMeal,
    required this.onRemoveRecipe,
    required this.onResetWeek,
    required this.onFillEmptySlots,
    required this.onGoToRecipes,
    required this.onSelectAccompaniment,
    required this.onRemoveAccompaniment,
    required this.mealHistoryEntries,
    required this.onRecordCookedRecipe,
  });

  final List<Recipe> recipes;
  final Map<String, String> weeklyPlanning;
  final Future<void> Function(String slotId, Recipe recipe) onSelectRecipe;
  final Future<void> Function(String slotId) onRemoveRecipe;
  final Future<void> Function() onResetWeek;
  final Future<void> Function({bool isVacationMode}) onFillEmptySlots;
  final VoidCallback onGoToRecipes;
  final Future<void> Function(String slotId, String label) onSetSpecialMeal;
  final Future<void> Function(String slotId, Recipe recipe)
  onSelectAccompaniment;
  final Future<void> Function(String slotId) onRemoveAccompaniment;
  final List<MealHistoryEntry> mealHistoryEntries;
  final Future<bool> Function({
    required Recipe recipe,
    required DateTime cookedAt,
    required String mealLabel,
    String? sourcePlanningSlotId,
  })
  onRecordCookedRecipe;

  void openCookingScreen(BuildContext context, Recipe recipe, String slotId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) {
          return CookingScreen(
            recipe: recipe,
            availableRecipes: recipes,
            sourcePlanningSlotId: slotId,
            onRecordCooked: onRecordCookedRecipe,
          );
        },
      ),
    );
  }

  Recipe? getRecipeForSlot(String slotId) {
    final recipeId = getMainRecipeIdFromPlanningValue(weeklyPlanning[slotId]);

    if (recipeId == null) {
      return null;
    }

    for (final recipe in recipes) {
      if (recipe.id == recipeId) {
        return recipe;
      }
    }

    return null;
  }

  Recipe? getAccompanimentForSlot(String slotId) {
    final recipeId = getAccompanimentRecipeIdFromPlanningValue(
      weeklyPlanning[slotId],
    );

    if (recipeId == null) {
      return null;
    }

    for (final recipe in recipes) {
      if (recipe.id == recipeId) {
        return recipe;
      }
    }

    return null;
  }

  String? getSpecialMealForSlot(String slotId) {
    final value = weeklyPlanning[slotId];

    if (!isSpecialMealValue(value)) {
      return null;
    }

    return getSpecialMealLabel(value!);
  }

  Future<void> openSpecialMealDialog(
    BuildContext context,
    MealSlot slot,
  ) async {
    String customLabel =
        getSpecialMealForSlot(slot.id) ?? defaultSpecialMealLabel;

    final selectedLabel = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Repas spécial — ${slot.label}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Indique un repas sans recette associée.'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final label in quickSpecialMealLabels)
                      ActionChip(
                        label: Text(label),
                        onPressed: () {
                          Navigator.of(dialogContext).pop(label);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  initialValue: customLabel,
                  decoration: const InputDecoration(
                    labelText: 'Libellé personnalisé',
                    hintText: 'Ex : Restaurant italien',
                    prefixIcon: Icon(Icons.edit_outlined),
                  ),
                  textInputAction: TextInputAction.done,
                  onChanged: (value) {
                    customLabel = value;
                  },
                  onFieldSubmitted: (value) {
                    Navigator.of(dialogContext).pop(value);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(customLabel);
              },
              child: const Text('Valider'),
            ),
          ],
        );
      },
    );

    if (selectedLabel == null) {
      return;
    }

    await onSetSpecialMeal(slot.id, selectedLabel);

    if (!context.mounted) {
      return;
    }

    Navigator.of(context).pop();
  }

  void openRecipeSelector(BuildContext context, MealSlot slot) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final selectedRecipe = getRecipeForSlot(slot.id);
        final specialMealLabel = getSpecialMealForSlot(slot.id);
        final isPlanned = selectedRecipe != null || specialMealLabel != null;

        return _RecipeSelectorSheet(
          slot: slot,
          recipes: recipes,
          selectedRecipe: selectedRecipe,
          specialMealLabel: specialMealLabel,
          onSelectRecipe: (recipe) async {
            await onSelectRecipe(slot.id, recipe);

            if (!sheetContext.mounted) {
              return;
            }

            Navigator.of(sheetContext).pop();
          },
          onSetSpecialMeal: () async {
            await openSpecialMealDialog(sheetContext, slot);
          },
          onClearSlot: isPlanned
              ? () async {
                  await onRemoveRecipe(slot.id);

                  if (!sheetContext.mounted) {
                    return;
                  }

                  Navigator.of(sheetContext).pop();
                }
              : null,
        );
      },
    );
  }

  void openAccompanimentSelector(BuildContext context, MealSlot slot) {
    final selectedAccompaniment = getAccompanimentForSlot(slot.id);

    final accompanimentRecipes =
        recipes.where((recipe) {
          return recipe.tags.contains('Accompagnement');
        }).toList()..sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return FractionallySizedBox(
          heightFactor: 0.82,
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Choisir un accompagnement',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  slot.label,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                if (accompanimentRecipes.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(18),
                      child: Text(
                        'Aucune recette avec le tag “Accompagnement”.',
                      ),
                    ),
                  ),
                for (final recipe in accompanimentRecipes)
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(child: Text(recipe.emoji)),
                      title: Text(recipe.name),
                      subtitle: Text(
                        recipe.timeSummaryText.isEmpty
                            ? 'Accompagnement'
                            : recipe.timeSummaryText,
                      ),
                      trailing: selectedAccompaniment?.id == recipe.id
                          ? const Icon(Icons.check_circle)
                          : null,
                      onTap: () async {
                        await onSelectAccompaniment(slot.id, recipe);

                        if (!sheetContext.mounted) {
                          return;
                        }

                        Navigator.of(sheetContext).pop();
                      },
                    ),
                  ),
                if (selectedAccompaniment != null) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await onRemoveAccompaniment(slot.id);

                      if (!sheetContext.mounted) {
                        return;
                      }

                      Navigator.of(sheetContext).pop();
                    },
                    icon: const Icon(Icons.close),
                    label: const Text('Retirer l’accompagnement'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void showMealHistorySheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return _MealHistorySheet(entries: mealHistoryEntries);
      },
    );
  }

  IconData getMealIcon(String meal) {
    if (meal == 'Midi') {
      return Icons.wb_sunny_outlined;
    }

    return Icons.nightlight_outlined;
  }

  Future<void> confirmResetWeek(BuildContext context) async {
    final shouldReset = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Réinitialiser la semaine ?'),
          content: const Text(
            'Le planning sera vidé et la liste de courses sera décochée. '
            'Tes recettes seront conservées.',
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
              child: const Text('Réinitialiser'),
            ),
          ],
        );
      },
    );

    if (shouldReset != true) {
      return;
    }

    await onResetWeek();
  }

  Future<void> confirmFillEmptySlots(BuildContext context) async {
    final emptySlotsCount = mealSlots.where((slot) {
      return !weeklyPlanning.containsKey(slot.id);
    }).length;

    if (emptySlotsCount == 0) {
      await onFillEmptySlots();
      return;
    }

    final autoFillOptions = await showDialog<_AutoFillOptions>(
      context: context,
      builder: (context) {
        var isVacationMode = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Remplir automatiquement ?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '$emptySlotsCount repas vide(s) seront remplis avec des '
                    'recettes choisies automatiquement. Les repas deja remplis '
                    'ne seront pas modifies.',
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.luggage_outlined),
                    title: const Text('Mode vacances'),
                    subtitle: const Text(
                      'Evite le four et favorise les recettes simples.',
                    ),
                    value: isVacationMode,
                    onChanged: (value) {
                      setDialogState(() {
                        isVacationMode = value;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(
                      context,
                    ).pop(_AutoFillOptions(isVacationMode: isVacationMode));
                  },
                  child: const Text('Remplir'),
                ),
              ],
            );
          },
        );
      },
    );
    if (autoFillOptions == null) {
      return;
    }

    await onFillEmptySlots(isVacationMode: autoFillOptions.isVacationMode);
  }

  String buildWeeklyPlanningShareText() {
    final buffer = StringBuffer();

    buffer.writeln('Planning repas de la semaine');
    buffer.writeln();

    for (final day in mealSlotDays) {
      final dayLines = <String>[];

      for (final slot in getMealSlotsForDay(day)) {
        final recipe = getRecipeForSlot(slot.id);
        final accompaniment = getAccompanimentForSlot(slot.id);
        final specialMealLabel = getSpecialMealForSlot(slot.id);

        if (specialMealLabel != null) {
          dayLines.add('${slot.meal} : $specialMealLabel');
          continue;
        }

        if (recipe == null) {
          continue;
        }

        if (accompaniment == null) {
          dayLines.add('${slot.meal} : ${recipe.name}');
        } else {
          dayLines.add('${slot.meal} : ${recipe.name} + ${accompaniment.name}');
        }
      }

      if (dayLines.isEmpty) {
        continue;
      }

      buffer.writeln(day);
      for (final line in dayLines) {
        buffer.writeln(line);
      }
      buffer.writeln();
    }

    return buffer.toString().trim();
  }

  Future<void> shareWeeklyPlanning(BuildContext context) async {
    if (weeklyPlanning.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Le planning est vide pour le moment.')),
      );

      return;
    }

    final shareText = buildWeeklyPlanningShareText();

    await SharePlus.instance.share(
      ShareParams(text: shareText, subject: 'Planning repas de la semaine'),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (recipes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [_EmptyPlanningCard(onGoToRecipes: onGoToRecipes)],
        ),
      );
    }

    final plannedMealsCount = weeklyPlanning.length;
    final totalMealsCount = mealSlots.length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _PlanningHeader(
          plannedMealsCount: plannedMealsCount,
          totalMealsCount: totalMealsCount,
          onFillEmptySlots: weeklyPlanning.length == mealSlots.length
              ? null
              : () async {
                  await confirmFillEmptySlots(context);
                },
          onShare: weeklyPlanning.isEmpty
              ? null
              : () async {
                  await shareWeeklyPlanning(context);
                },
          onReset: weeklyPlanning.isEmpty
              ? null
              : () async {
                  await confirmResetWeek(context);
                },
          onShowMealHistory: () {
            showMealHistorySheet(context);
          },
          mealHistoryEntriesCount: mealHistoryEntries.length,
        ),
        const SizedBox(height: 16),
        for (final day in mealSlotDays)
          _DayPlanningCard(
            day: day,
            slots: getMealSlotsForDay(day),
            getRecipeForSlot: getRecipeForSlot,
            getSpecialMealForSlot: getSpecialMealForSlot,
            getMealIcon: getMealIcon,
            getAccompanimentForSlot: getAccompanimentForSlot,
            onSelectAccompaniment: (slot) {
              openAccompanimentSelector(context, slot);
            },
            onSelectSlot: (slot) {
              openRecipeSelector(context, slot);
            },
            onStartCooking: (slot, recipe) {
              openCookingScreen(context, recipe, slot.id);
            },
            onRemoveSlot: onRemoveRecipe,
          ),
      ],
    );
  }
}

class _PlanningHeader extends StatelessWidget {
  const _PlanningHeader({
    required this.plannedMealsCount,
    required this.totalMealsCount,
    required this.onFillEmptySlots,
    required this.onShare,
    required this.onReset,
    required this.onShowMealHistory,
    required this.mealHistoryEntriesCount,
  });

  final int plannedMealsCount;
  final int totalMealsCount;
  final Future<void> Function()? onFillEmptySlots;
  final Future<void> Function()? onShare;
  final Future<void> Function()? onReset;
  final VoidCallback onShowMealHistory;
  final int mealHistoryEntriesCount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final progress = totalMealsCount == 0
        ? 0.0
        : plannedMealsCount / totalMealsCount;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.calendar_month_outlined,
            size: 36,
            color: colorScheme.onPrimaryContainer,
          ),
          const SizedBox(height: 14),
          Text(
            'Planning de la semaine',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: colorScheme.onPrimaryContainer,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$plannedMealsCount/$totalMealsCount repas planifié(s)',
            style: TextStyle(
              color: colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: colorScheme.surface.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: onFillEmptySlots,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Auto'),
              ),
              OutlinedButton.icon(
                onPressed: onShare,
                icon: const Icon(Icons.share),
                label: const Text('Partager'),
              ),
              OutlinedButton.icon(
                onPressed: onShowMealHistory,
                icon: const Icon(Icons.history),
                label: Text('Historique ($mealHistoryEntriesCount)'),
              ),
              OutlinedButton.icon(
                onPressed: onReset,
                icon: const Icon(Icons.refresh),
                label: const Text('Reset'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MealHistorySheet extends StatelessWidget {
  const _MealHistorySheet({required this.entries});

  final List<MealHistoryEntry> entries;

  @override
  Widget build(BuildContext context) {
    final sortedEntries = [...entries]
      ..sort((a, b) => b.cookedAt.compareTo(a.cookedAt));
    final recentEntries = sortedEntries.take(30).toList();

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        shrinkWrap: true,
        children: [
          Text(
            'Historique des repas',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (recentEntries.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Aucun repas réalisé enregistré pour le moment.'),
              ),
            )
          else
            for (final entry in recentEntries)
              Card(
                child: ListTile(
                  leading: CircleAvatar(child: Text(entry.recipeEmoji)),
                  title: Text(entry.recipeName),
                  subtitle: Text(
                    '${entry.slotLabel} - ${formatHistoryDate(entry.cookedAt)}',
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

String formatHistoryDate(DateTime date) {
  String twoDigits(int value) {
    return value.toString().padLeft(2, '0');
  }

  return '${twoDigits(date.day)}/${twoDigits(date.month)}/${date.year}';
}

class _DayPlanningCard extends StatelessWidget {
  const _DayPlanningCard({
    required this.day,
    required this.slots,
    required this.getSpecialMealForSlot,
    required this.getRecipeForSlot,
    required this.getMealIcon,
    required this.onSelectSlot,
    required this.onStartCooking,
    required this.onRemoveSlot,
    required this.getAccompanimentForSlot,
    required this.onSelectAccompaniment,
  });

  final String day;
  final List<MealSlot> slots;
  final Recipe? Function(String slotId) getRecipeForSlot;
  final String? Function(String slotId) getSpecialMealForSlot;
  final IconData Function(String meal) getMealIcon;
  final void Function(MealSlot slot) onSelectSlot;
  final Future<void> Function(String slotId) onRemoveSlot;
  final void Function(MealSlot slot, Recipe recipe) onStartCooking;
  final Recipe? Function(String slotId) getAccompanimentForSlot;
  final void Function(MealSlot slot) onSelectAccompaniment;

  @override
  Widget build(BuildContext context) {
    final plannedSlots = slots.where((slot) {
      return getRecipeForSlot(slot.id) != null ||
          getSpecialMealForSlot(slot.id) != null;
    }).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  day,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                _SmallBadge(label: '$plannedSlots/${slots.length}'),
              ],
            ),
            const SizedBox(height: 10),
            for (final slot in slots)
              _MealSlotTile(
                slot: slot,
                recipe: getRecipeForSlot(slot.id),
                specialMealLabel: getSpecialMealForSlot(slot.id),
                accompaniment: getAccompanimentForSlot(slot.id),
                onSelectAccompaniment: () {
                  onSelectAccompaniment(slot);
                },
                icon: getMealIcon(slot.meal),
                onTap: () {
                  onSelectSlot(slot);
                },
                onStartCooking: getRecipeForSlot(slot.id) == null
                    ? null
                    : () {
                        onStartCooking(slot, getRecipeForSlot(slot.id)!);
                      },
                onRemove:
                    getRecipeForSlot(slot.id) == null &&
                        getSpecialMealForSlot(slot.id) == null
                    ? null
                    : () async {
                        await onRemoveSlot(slot.id);
                      },
              ),
          ],
        ),
      ),
    );
  }
}

class _MealSlotTile extends StatelessWidget {
  const _MealSlotTile({
    required this.slot,
    required this.recipe,
    required this.icon,
    required this.onTap,
    required this.onRemove,
    required this.specialMealLabel,
    required this.onStartCooking,
    required this.accompaniment,
    required this.onSelectAccompaniment,
  });

  final MealSlot slot;
  final Recipe? recipe;
  final IconData icon;
  final VoidCallback onTap;
  final Future<void> Function()? onRemove;
  final String? specialMealLabel;
  final VoidCallback? onStartCooking;
  final Recipe? accompaniment;
  final VoidCallback onSelectAccompaniment;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selectedRecipe = recipe;
    final hasSpecialMeal = specialMealLabel != null;
    final isPlanned = selectedRecipe != null || hasSpecialMeal;
    final canHaveAccompaniment =
        selectedRecipe != null &&
        !selectedRecipe.tags.contains('Plat complet') &&
        !hasSpecialMeal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: !isPlanned
            ? colorScheme.surface
            : colorScheme.secondaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: selectedRecipe != null && onStartCooking != null
              ? onStartCooking
              : onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selectedRecipe == null && !hasSpecialMeal
                              ? colorScheme.surfaceContainerHighest
                              : colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: selectedRecipe != null
                            ? Text(
                                selectedRecipe.emoji,
                                style: const TextStyle(fontSize: 23),
                              )
                            : hasSpecialMeal
                            ? Icon(
                                Icons.restaurant_outlined,
                                color: colorScheme.primary,
                              )
                            : Icon(icon, color: colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: !isPlanned
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    slot.meal,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    'Aucune recette sélectionnée',
                                    style: TextStyle(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    slot.meal,
                                    style: TextStyle(
                                      color: colorScheme.onSurfaceVariant,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    selectedRecipe?.name ?? specialMealLabel!,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  if (accompaniment != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 3),
                                      child: Text(
                                        '+ ${accompaniment!.emoji} ${accompaniment!.name}',
                                        style: TextStyle(
                                          color: colorScheme.onSurfaceVariant,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  if (selectedRecipe != null &&
                                      selectedRecipe.timeSummaryText.isNotEmpty)
                                    Text(
                                      selectedRecipe.timeSummaryText,
                                      style: TextStyle(
                                        color: colorScheme.onSurfaceVariant,
                                        fontSize: 13,
                                      ),
                                    ),
                                  if (hasSpecialMeal)
                                    Text(
                                      'Repas spécial',
                                      style: TextStyle(
                                        color: colorScheme.onSurfaceVariant,
                                        fontSize: 13,
                                      ),
                                    ),
                                ],
                              ),
                      ),
                      Icon(
                        selectedRecipe != null
                            ? Icons.play_arrow
                            : Icons.chevron_right,
                      ),
                    ],
                  ),
                  if (isPlanned) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (canHaveAccompaniment)
                          _CompactActionButton(
                            icon: accompaniment == null
                                ? Icons.add_circle_outline
                                : Icons.rice_bowl,
                            label: accompaniment == null
                                ? 'Accomp.'
                                : 'Accomp.',
                            onPressed: onSelectAccompaniment,
                          ),
                        if (isPlanned)
                          _CompactActionButton(
                            icon: Icons.edit_outlined,
                            label: 'Modifier',
                            onPressed: onTap,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactActionButton extends StatelessWidget {
  const _CompactActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ],
    );

    final style = ButtonStyle(
      visualDensity: VisualDensity.standard,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      minimumSize: const WidgetStatePropertyAll(Size(0, 38)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
    );
    return OutlinedButton(onPressed: onPressed, style: style, child: child);
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

class _EmptyPlanningCard extends StatelessWidget {
  const _EmptyPlanningCard({required this.onGoToRecipes});

  final VoidCallback onGoToRecipes;

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
                Icons.calendar_month_outlined,
                size: 38,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Ton planning est vide',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Ajoute d’abord une recette pour pouvoir remplir ta semaine.',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onGoToRecipes,
              icon: const Icon(Icons.add),
              label: const Text('Ajouter une recette'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecipeSelectorSheet extends StatefulWidget {
  const _RecipeSelectorSheet({
    required this.slot,
    required this.recipes,
    required this.selectedRecipe,
    required this.specialMealLabel,
    required this.onSelectRecipe,
    required this.onSetSpecialMeal,
    required this.onClearSlot,
  });

  final MealSlot slot;
  final List<Recipe> recipes;
  final Recipe? selectedRecipe;
  final String? specialMealLabel;
  final Future<void> Function(Recipe recipe) onSelectRecipe;
  final Future<void> Function() onSetSpecialMeal;
  final Future<void> Function()? onClearSlot;

  @override
  State<_RecipeSelectorSheet> createState() => _RecipeSelectorSheetState();
}

class _RecipeSelectorSheetState extends State<_RecipeSelectorSheet> {
  final searchController = TextEditingController();

  String searchQuery = '';

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  List<Recipe> get filteredRecipes {
    final query = searchQuery.trim().toLowerCase();

    final recipes = widget.recipes.where((recipe) {
      if (query.isEmpty) {
        return true;
      }

      final ingredientsText = recipe.ingredients
          .map((ingredient) => ingredient.name)
          .join(' ')
          .toLowerCase();

      final tagsText = recipe.tags.join(' ').toLowerCase();

      final searchableText = [
        recipe.name,
        recipe.metadataText,
        tagsText,
        ingredientsText,
      ].join(' ').toLowerCase();

      return searchableText.contains(query);
    }).toList();

    recipes.sort((a, b) {
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return recipes;
  }

  void updateSearch(String value) {
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final recipes = filteredRecipes;
    final hasSearch = searchQuery.trim().isNotEmpty;
    final hasCurrentSelection =
        widget.selectedRecipe != null || widget.specialMealLabel != null;

    return FractionallySizedBox(
      heightFactor: 0.92,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SelectorHeader(
                    slot: widget.slot,
                    selectedRecipe: widget.selectedRecipe,
                    specialMealLabel: widget.specialMealLabel,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      labelText: 'Rechercher une recette',
                      hintText: 'Nom, ingrédient, tag, durée...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: hasSearch
                          ? IconButton(
                              onPressed: clearSearch,
                              icon: const Icon(Icons.close),
                            )
                          : null,
                    ),
                    onChanged: updateSearch,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  _SpecialMealSelectorTile(
                    label: widget.specialMealLabel,
                    onTap: widget.onSetSpecialMeal,
                  ),
                  if (hasCurrentSelection && widget.onClearSlot != null) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: widget.onClearSlot,
                      icon: const Icon(Icons.close),
                      label: const Text('Vider ce repas'),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text(
                        'Recettes',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${recipes.length}/${widget.recipes.length}',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (recipes.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Icon(
                              Icons.search_off,
                              size: 42,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Aucune recette trouvée pour "$searchQuery".',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  for (final recipe in recipes)
                    _RecipeSelectorTile(
                      recipe: recipe,
                      isSelected: widget.selectedRecipe?.id == recipe.id,
                      onTap: () async {
                        await widget.onSelectRecipe(recipe);
                      },
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

class _SelectorHeader extends StatelessWidget {
  const _SelectorHeader({
    required this.slot,
    required this.selectedRecipe,
    required this.specialMealLabel,
  });

  final MealSlot slot;
  final Recipe? selectedRecipe;
  final String? specialMealLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final title =
        selectedRecipe?.name ?? specialMealLabel ?? 'Aucun repas choisi';
    final emoji = selectedRecipe?.emoji ?? '🍽️';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(18),
            ),
            child: selectedRecipe != null
                ? Text(emoji, style: const TextStyle(fontSize: 32))
                : Icon(
                    specialMealLabel != null
                        ? Icons.restaurant_outlined
                        : Icons.calendar_month_outlined,
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
                  slot.label,
                  style: TextStyle(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: TextStyle(
                    color: colorScheme.onPrimaryContainer,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                if (selectedRecipe != null &&
                    selectedRecipe!.metadataText.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    selectedRecipe!.metadataText,
                    style: TextStyle(color: colorScheme.onPrimaryContainer),
                  ),
                ],
                if (specialMealLabel != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Repas spécial',
                    style: TextStyle(color: colorScheme.onPrimaryContainer),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SpecialMealSelectorTile extends StatelessWidget {
  const _SpecialMealSelectorTile({required this.label, required this.onTap});

  final String? label;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = label != null;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () async {
          await onTap();
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: isSelected
                      ? colorScheme.primaryContainer
                      : colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.restaurant_outlined,
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label ?? 'Repas spécial',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      'Restaurant, repas extérieur, invités, restes...',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle, color: colorScheme.primary)
              else
                const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecipeSelectorTile extends StatelessWidget {
  const _RecipeSelectorTile({
    required this.recipe,
    required this.isSelected,
    required this.onTap,
  });

  final Recipe recipe;
  final bool isSelected;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () async {
          await onTap();
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected
                      ? colorScheme.primaryContainer
                      : colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(recipe.emoji, style: const TextStyle(fontSize: 26)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recipe.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    if (recipe.timeSummaryText.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        recipe.timeSummaryText,
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                    ],
                    if (recipe.ingredients.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        recipe.ingredients
                            .take(4)
                            .map((ingredient) => ingredient.name)
                            .join(', '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isSelected)
                Icon(Icons.check_circle, color: colorScheme.primary)
              else
                const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
