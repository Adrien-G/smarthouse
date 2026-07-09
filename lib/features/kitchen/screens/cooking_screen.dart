import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../data/recipe_tags.dart';
import '../models/recipe.dart';

class CookingStep {
  const CookingStep({required this.title, required this.text});

  final String title;
  final String text;
}

class CookingTimer {
  const CookingTimer({
    required this.id,
    required this.duration,
    required this.remainingDuration,
    required this.label,
    this.hasFinished = false,
  });

  final int id;
  final Duration duration;
  final Duration remainingDuration;
  final String label;
  final bool hasFinished;

  bool get isRunning => remainingDuration.inSeconds > 0 && !hasFinished;

  CookingTimer copyWith({
    Duration? duration,
    Duration? remainingDuration,
    String? label,
    bool? hasFinished,
  }) {
    return CookingTimer(
      id: id,
      duration: duration ?? this.duration,
      remainingDuration: remainingDuration ?? this.remainingDuration,
      label: label ?? this.label,
      hasFinished: hasFinished ?? this.hasFinished,
    );
  }
}

class CookingTimerSuggestion {
  const CookingTimerSuggestion({required this.duration, required this.label});

  final Duration duration;
  final String label;
}

class CookingScreen extends StatefulWidget {
  const CookingScreen({
    super.key,
    required this.recipe,
    this.availableRecipes = const [],
    this.sourcePlanningSlotId,
    this.onRecordCooked,
  });

  final Recipe recipe;
  final List<Recipe> availableRecipes;
  final String? sourcePlanningSlotId;
  final Future<bool> Function({
    required Recipe recipe,
    required DateTime cookedAt,
    required String mealLabel,
    String? sourcePlanningSlotId,
  })?
  onRecordCooked;

  @override
  State<CookingScreen> createState() => _CookingScreenState();
}

class _CookingScreenState extends State<CookingScreen> {
  int currentStepIndex = 0;
  late List<CookingStep> activeCookingSteps;
  final Set<String> insertedReusablePreparationIds = {};

  late final ConfettiController confettiController;
  late final AudioPlayer timerAudioPlayer;

  Timer? timerTicker;
  Timer? timerAlertStopTimer;
  final List<CookingTimer> cookingTimers = [];
  int nextTimerId = 0;
  bool isTimerAlertPlaying = false;

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

    final hasBulletList = RegExp(
      r'(^|\n)\s*[-\u2022*]\s+',
    ).hasMatch(cleanedSteps);

    if (hasBulletList) {
      return [cleanPreparationStepBlock(cleanedSteps)];
    }

    return cleanedSteps
        .split('\n')
        .map(cleanPreparationStep)
        .where((step) => step.isNotEmpty && step != 'À compléter.')
        .toList();
  }

  List<CookingStep> buildInitialCookingSteps() {
    final ingredientLines = widget.recipe.ingredients
        .map((ingredient) => '• ${ingredient.displayText}')
        .join('\n');

    return [
      CookingStep(
        title: 'Rassembler les ingrédients',
        text: ingredientLines.isEmpty
            ? 'Prépare tous les ingrédients nécessaires avant de commencer.'
            : 'Prépare tous les ingrédients nécessaires :\n\n$ingredientLines',
      ),
      const CookingStep(
        title: 'Se laver les mains',
        text:
            'Lave-toi soigneusement les mains avant de commencer la préparation.',
      ),
      for (final step in recipePreparationSteps)
        CookingStep(title: 'Préparation', text: step),
    ];
  }

  List<String> get recipePreparationSteps {
    return splitPreparationSteps(widget.recipe.steps);
  }

  List<CookingStep> get cookingSteps => activeCookingSteps;

  bool get hasSteps => activeCookingSteps.isNotEmpty;

  bool get canGoPrevious => currentStepIndex > 0;

  bool get isLastStep => currentStepIndex == activeCookingSteps.length - 1;

  double get progress {
    if (!hasSteps) {
      return 0;
    }

    return (currentStepIndex + 1) / activeCookingSteps.length;
  }

  @override
  void initState() {
    super.initState();

    activeCookingSteps = buildInitialCookingSteps();
    confettiController = ConfettiController(
      duration: const Duration(seconds: 10),
    );
    timerAudioPlayer = AudioPlayer();
    unawaited(WakelockPlus.enable());
  }

  @override
  void dispose() {
    unawaited(WakelockPlus.disable());
    timerTicker?.cancel();
    timerAlertStopTimer?.cancel();
    timerAudioPlayer.dispose();
    confettiController.dispose();

    super.dispose();
  }

  String cleanPreparationStep(String value) {
    return value
        .trim()
        .replaceFirst(RegExp(r'^[-\u2022*]\s*'), '')
        .replaceFirst(RegExp(r'^\d+[.)]\s*'), '')
        .trim();
  }

  String cleanPreparationStepBlock(String value) {
    return value.trim().replaceFirst(RegExp(r'^\d+[.)]\s*'), '').trim();
  }

  void startTimerTickerIfNeeded() {
    if (timerTicker?.isActive == true) {
      return;
    }

    timerTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }

      final finishedTimers = <CookingTimer>[];

      setState(() {
        for (var index = 0; index < cookingTimers.length; index++) {
          final timer = cookingTimers[index];

          if (!timer.isRunning) {
            continue;
          }

          if (timer.remainingDuration.inSeconds <= 1) {
            final finishedTimer = timer.copyWith(
              remainingDuration: Duration.zero,
              hasFinished: true,
            );
            cookingTimers[index] = finishedTimer;
            finishedTimers.add(finishedTimer);
          } else {
            cookingTimers[index] = timer.copyWith(
              remainingDuration:
                  timer.remainingDuration - const Duration(seconds: 1),
            );
          }
        }
      });

      if (finishedTimers.isNotEmpty) {
        unawaited(startTimerFinishedAlert());
      }

      if (!cookingTimers.any((timer) => timer.isRunning)) {
        timerTicker?.cancel();
        timerTicker = null;
      }
    });
  }

  void addOrUpdateTimer({
    required Duration duration,
    required String label,
    int? timerId,
  }) {
    if (duration.inSeconds <= 0) {
      return;
    }

    setState(() {
      final timerIndex = timerId == null
          ? -1
          : cookingTimers.indexWhere((timer) => timer.id == timerId);
      final timer = CookingTimer(
        id: timerIndex == -1 ? nextTimerId++ : timerId!,
        duration: duration,
        remainingDuration: duration,
        label: label.trim(),
      );

      if (timerIndex == -1) {
        cookingTimers.add(timer);
      } else {
        cookingTimers[timerIndex] = timer;
      }
    });

    startTimerTickerIfNeeded();
    syncTimerFinishedAlert();
  }

  void removeTimer(CookingTimer timer) {
    setState(() {
      cookingTimers.removeWhere((item) => item.id == timer.id);
    });

    if (!cookingTimers.any((timer) => timer.isRunning)) {
      timerTicker?.cancel();
      timerTicker = null;
    }

    syncTimerFinishedAlert();
  }

  void startSuggestedTimer(CookingTimerSuggestion suggestion) {
    addOrUpdateTimer(duration: suggestion.duration, label: suggestion.label);
  }

  List<CookingTimerSuggestion> getTimerSuggestionsForStep({
    required CookingStep step,
    required int stepNumber,
  }) {
    final suggestions = <CookingTimerSuggestion>[];
    final seenDurations = <int>{};

    void addSuggestion(Duration duration) {
      final totalSeconds = duration.inSeconds;

      if (totalSeconds <= 0 || duration.inHours > 8) {
        return;
      }

      if (!seenDurations.add(totalSeconds)) {
        return;
      }

      suggestions.add(
        CookingTimerSuggestion(
          duration: duration,
          label: getSuggestedTimerLabel(step.text, stepNumber),
        ),
      );
    }

    final compactHourPattern = RegExp(
      r'\b(\d{1,2})\s*h\s*(\d{1,2})?\b',
      caseSensitive: false,
    );

    for (final match in compactHourPattern.allMatches(step.text)) {
      final hours = int.tryParse(match.group(1) ?? '') ?? 0;
      final minutes = int.tryParse(match.group(2) ?? '') ?? 0;

      addSuggestion(Duration(hours: hours, minutes: minutes));
    }

    final hourMinutePattern = RegExp(
      r'\b(?:(\d{1,2})\s*(?:heure|heures)\s*)?'
      r'(\d{1,3})\s*(?:min|mn|minute|minutes)\b',
      caseSensitive: false,
    );

    for (final match in hourMinutePattern.allMatches(step.text)) {
      final hours = int.tryParse(match.group(1) ?? '') ?? 0;
      final minutes = int.tryParse(match.group(2) ?? '') ?? 0;

      addSuggestion(Duration(hours: hours, minutes: minutes));
    }

    return suggestions.take(4).toList();
  }

  String getSuggestedTimerLabel(String stepText, int stepNumber) {
    final normalizedText = normalizeTimerSuggestionText(stepText);

    if (normalizedText.contains('four')) {
      return 'Four';
    }

    if (normalizedText.contains('pate') ||
        normalizedText.contains('spaghetti')) {
      return 'Pâtes';
    }

    if (normalizedText.contains('riz')) {
      return 'Riz';
    }

    if (normalizedText.contains('repos') ||
        normalizedText.contains('reposer')) {
      return 'Repos';
    }

    if (normalizedText.contains('cuisson') ||
        normalizedText.contains('cuire') ||
        normalizedText.contains('mijoter')) {
      return 'Cuisson';
    }

    return 'Étape $stepNumber';
  }

  String normalizeTimerSuggestionText(String value) {
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

  List<Recipe> getReusablePreparationMatches(CookingStep step) {
    final normalizedStep = normalizeReusablePreparationText(step.text);

    return widget.availableRecipes.where((recipe) {
      if (recipe.id == widget.recipe.id ||
          insertedReusablePreparationIds.contains(recipe.id) ||
          !recipe.tags.contains(reusablePreparationTag)) {
        return false;
      }

      return getReusablePreparationTerms(recipe).any((term) {
        return term.isNotEmpty && normalizedStep.contains(term);
      });
    }).toList();
  }

  List<String> getReusablePreparationTerms(Recipe recipe) {
    final normalizedName = normalizeReusablePreparationText(recipe.name);
    final terms = <String>{normalizedName};

    for (final prefix in ['sauce ', 'préparation ', 'preparation ']) {
      if (normalizedName.startsWith(prefix)) {
        terms.add(normalizedName.substring(prefix.length).trim());
      }
    }

    for (final word in normalizedName.split(' ')) {
      if (word.length >= 5) {
        terms.add(word);
      }
    }

    return terms.where((term) => term.isNotEmpty).toList();
  }

  String normalizeReusablePreparationText(String value) {
    return normalizeTimerSuggestionText(value)
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  void insertReusablePreparation(Recipe preparation) {
    final preparationSteps = splitPreparationSteps(preparation.steps);

    if (preparationSteps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'La préparation "${preparation.name}" ne contient pas encore d’étapes.',
          ),
        ),
      );
      return;
    }

    setState(() {
      activeCookingSteps.insertAll(currentStepIndex + 1, [
        for (final step in preparationSteps)
          CookingStep(title: preparation.name, text: step),
      ]);
      insertedReusablePreparationIds.add(preparation.id);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Étapes de ${preparation.name} ajoutées.')),
    );
  }

  Future<void> openTimerSettings({CookingTimer? timer}) async {
    final settings = await showDialog<_TimerSettings>(
      context: context,
      builder: (context) {
        return _TimerSettingsDialog(
          initialDuration: timer?.duration ?? Duration.zero,
          initialLabel: timer?.label ?? '',
        );
      },
    );

    if (settings == null) {
      return;
    }

    addOrUpdateTimer(
      duration: settings.duration,
      label: settings.label,
      timerId: timer?.id,
    );
  }

  Future<void> startTimerFinishedAlert() async {
    if (isTimerAlertPlaying) {
      return;
    }

    isTimerAlertPlaying = true;
    timerAlertStopTimer?.cancel();
    timerAlertStopTimer = Timer(const Duration(minutes: 1), () {
      unawaited(stopTimerFinishedAlert());
    });

    try {
      await timerAudioPlayer.setReleaseMode(ReleaseMode.loop);
      await timerAudioPlayer.stop();

      if (!isTimerAlertPlaying ||
          !cookingTimers.any((timer) => timer.hasFinished)) {
        return;
      }

      await timerAudioPlayer.play(AssetSource('sounds/timer_done.wav'));
    } catch (_) {
      timerAlertStopTimer?.cancel();
      timerAlertStopTimer = null;
      isTimerAlertPlaying = false;
    }
  }

  Future<void> stopTimerFinishedAlert() async {
    if (!isTimerAlertPlaying) {
      return;
    }

    timerAlertStopTimer?.cancel();
    timerAlertStopTimer = null;
    isTimerAlertPlaying = false;
    await timerAudioPlayer.stop();
  }

  void syncTimerFinishedAlert() {
    if (cookingTimers.any((timer) => timer.hasFinished)) {
      return;
    }

    unawaited(stopTimerFinishedAlert());
  }

  void goPrevious() {
    if (!canGoPrevious) {
      return;
    }

    setState(() {
      currentStepIndex--;
    });
  }

  void goNext() {
    if (isLastStep) {
      finishCooking();
      return;
    }

    setState(() {
      currentStepIndex++;
    });
  }

  Future<void> finishCooking() async {
    timerTicker?.cancel();
    confettiController.play();

    await Future.delayed(const Duration(milliseconds: 2000));

    if (!mounted) {
      return;
    }

    final shouldClose = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return _CookingFinishedDialog(
          recipe: widget.recipe,
          sourcePlanningSlotId: widget.sourcePlanningSlotId,
          onRecordCooked: widget.onRecordCooked,
        );
      },
    );

    if (!mounted) {
      return;
    }

    if (shouldClose == true) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = cookingSteps;
    final currentStep = hasSteps ? steps[currentStepIndex] : null;
    final reusablePreparationMatches = currentStep == null
        ? <Recipe>[]
        : getReusablePreparationMatches(currentStep);

    return Scaffold(
      appBar: AppBar(title: const Text('Préparation')),
      body: Stack(
        children: [
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                _CookingHeader(
                  recipe: widget.recipe,
                  currentStepIndex: currentStepIndex,
                  totalSteps: steps.length,
                  progress: progress,
                ),
                const SizedBox(height: 16),
                _IngredientsCard(recipe: widget.recipe),
                const SizedBox(height: 16),
                if (!hasSteps)
                  const _NoStepsCard()
                else
                  _CurrentStepCard(
                    stepNumber: currentStepIndex + 1,
                    stepTitle: currentStep!.title,
                    stepText: currentStep.text,
                    timerSuggestions: getTimerSuggestionsForStep(
                      step: currentStep,
                      stepNumber: currentStepIndex + 1,
                    ),
                    reusablePreparationMatches: reusablePreparationMatches,
                    onStartSuggestedTimer: startSuggestedTimer,
                    onInsertReusablePreparation: insertReusablePreparation,
                  ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              shouldLoop: false,
              numberOfParticles: 28,
              gravity: 0.25,
            ),
          ),
        ],
      ),
      bottomNavigationBar: hasSteps
          ? _CookingFooter(
              timer: _CookingTimersBar(
                timers: cookingTimers,
                onAddTimer: () {
                  openTimerSettings();
                },
                onEditTimer: (timer) {
                  openTimerSettings(timer: timer);
                },
                onRemoveTimer: removeTimer,
              ),
              navigation: _CookingNavigation(
                canGoPrevious: canGoPrevious,
                isLastStep: isLastStep,
                onPrevious: goPrevious,
                onNext: goNext,
              ),
            )
          : null,
    );
  }
}

class _CookingFinishedDialog extends StatefulWidget {
  const _CookingFinishedDialog({
    required this.recipe,
    required this.sourcePlanningSlotId,
    required this.onRecordCooked,
  });

  final Recipe recipe;
  final String? sourcePlanningSlotId;
  final Future<bool> Function({
    required Recipe recipe,
    required DateTime cookedAt,
    required String mealLabel,
    String? sourcePlanningSlotId,
  })?
  onRecordCooked;

  @override
  State<_CookingFinishedDialog> createState() => _CookingFinishedDialogState();
}

class _CookingFinishedDialogState extends State<_CookingFinishedDialog> {
  late DateTime cookedAt;
  late String mealLabel;
  bool isSaving = false;
  bool hasSaved = false;

  @override
  void initState() {
    super.initState();
    cookedAt = DateTime.now();
    mealLabel = suggestedMealLabel(cookedAt);
  }

  String suggestedMealLabel(DateTime date) {
    if (date.hour < 15) {
      return 'Midi';
    }

    return 'Soir';
  }

  String formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  String formatSavedLabel() {
    return '${formatDate(cookedAt)} - $mealLabel';
  }

  Future<void> pickCookedDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: cookedAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 7)),
    );

    if (pickedDate == null) {
      return;
    }

    setState(() {
      cookedAt = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        cookedAt.hour,
        cookedAt.minute,
      );
    });
  }

  Future<void> recordCookedRecipe() async {
    final onRecordCooked = widget.onRecordCooked;

    if (onRecordCooked == null || isSaving || hasSaved) {
      return;
    }

    setState(() {
      isSaving = true;
    });

    final wasAdded = await onRecordCooked(
      recipe: widget.recipe,
      cookedAt: cookedAt,
      mealLabel: mealLabel,
      sourcePlanningSlotId: widget.sourcePlanningSlotId,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      isSaving = false;
      hasSaved = true;
    });

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          wasAdded
              ? 'Repas ajouté à l’historique.'
              : 'Ce repas est déjà dans l’historique.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Bravo !'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('La recette "${widget.recipe.name}" est terminée.'),
          if (widget.onRecordCooked != null) ...[
            const SizedBox(height: 16),
            const Text(
              'Ajouter à l’historique ?',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: hasSaved ? null : pickCookedDate,
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text(formatDate(cookedAt)),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'Midi', label: Text('Midi')),
                ButtonSegment(value: 'Soir', label: Text('Soir')),
              ],
              selected: {mealLabel},
              onSelectionChanged: hasSaved
                  ? null
                  : (values) {
                      setState(() {
                        mealLabel = values.first;
                      });
                    },
            ),
            const SizedBox(height: 10),
            if (hasSaved)
              Text(
                'Enregistré pour ${formatSavedLabel()}.',
                style: const TextStyle(fontWeight: FontWeight.w700),
              )
            else
              FilledButton.icon(
                onPressed: isSaving ? null : recordCookedRecipe,
                icon: isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.history),
                label: const Text('Ajouter à l’historique'),
              ),
          ],
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(true);
          },
          child: const Text('Terminer'),
        ),
      ],
    );
  }
}

class _CookingHeader extends StatelessWidget {
  const _CookingHeader({
    required this.recipe,
    required this.currentStepIndex,
    required this.totalSteps,
    required this.progress,
  });

  final Recipe recipe;
  final int currentStepIndex;
  final int totalSteps;
  final double progress;

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
            children: [
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Text(recipe.emoji, style: const TextStyle(fontSize: 36)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recipe.name,
                      style: TextStyle(
                        color: colorScheme.onPrimaryContainer,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    if (recipe.metadataText.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        recipe.metadataText,
                        style: TextStyle(
                          color: colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (totalSteps > 0) ...[
            const SizedBox(height: 18),
            Text(
              'Étape ${currentStepIndex + 1} sur $totalSteps',
              style: TextStyle(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: colorScheme.surface.withValues(alpha: 0.55),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _IngredientsCard extends StatelessWidget {
  const _IngredientsCard({required this.recipe});

  final Recipe recipe;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: ExpansionTile(
        initiallyExpanded: false,
        leading: const Icon(Icons.shopping_basket_outlined),
        title: const Text(
          'Ingrédients',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text('${recipe.ingredients.length} ingrédient(s)'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          for (final ingredient in recipe.ingredients)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    ingredient.includeInShoppingList
                        ? Icons.circle
                        : Icons.remove_shopping_cart_outlined,
                    size: ingredient.includeInShoppingList ? 8 : 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      ingredient.displayText,
                      style: TextStyle(
                        color: ingredient.includeInShoppingList
                            ? colorScheme.onSurface
                            : colorScheme.onSurfaceVariant,
                      ),
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

class _CurrentStepCard extends StatelessWidget {
  const _CurrentStepCard({
    required this.stepNumber,
    required this.stepTitle,
    required this.stepText,
    required this.timerSuggestions,
    required this.reusablePreparationMatches,
    required this.onStartSuggestedTimer,
    required this.onInsertReusablePreparation,
  });

  final int stepNumber;
  final String stepText;
  final String stepTitle;
  final List<CookingTimerSuggestion> timerSuggestions;
  final List<Recipe> reusablePreparationMatches;
  final void Function(CookingTimerSuggestion suggestion) onStartSuggestedTimer;
  final void Function(Recipe recipe) onInsertReusablePreparation;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  child: Text(
                    '$stepNumber',
                    style: TextStyle(
                      color: colorScheme.primary,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    stepTitle,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              stepText,
              style: const TextStyle(
                fontSize: 22,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (timerSuggestions.isNotEmpty) ...[
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final suggestion in timerSuggestions)
                    _TimerSuggestionChip(
                      suggestion: suggestion,
                      onPressed: () {
                        onStartSuggestedTimer(suggestion);
                      },
                    ),
                ],
              ),
            ],
            if (reusablePreparationMatches.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preparation in reusablePreparationMatches)
                    ActionChip(
                      avatar: const Icon(Icons.add_circle_outline, size: 18),
                      label: Text('Insérer les étapes de ${preparation.name}'),
                      onPressed: () {
                        onInsertReusablePreparation(preparation);
                      },
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TimerSuggestionChip extends StatelessWidget {
  const _TimerSuggestionChip({
    required this.suggestion,
    required this.onPressed,
  });

  final CookingTimerSuggestion suggestion;
  final VoidCallback onPressed;

  String formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);

    if (hours > 0 && minutes > 0) {
      return '${hours}h${minutes.toString().padLeft(2, '0')}';
    }

    if (hours > 0) {
      return '${hours}h';
    }

    return '${duration.inMinutes} min';
  }

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: const Icon(Icons.timer_outlined, size: 18),
      label: Text(formatDuration(suggestion.duration)),
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _CookingFooter extends StatelessWidget {
  const _CookingFooter({required this.timer, required this.navigation});

  final Widget timer;
  final Widget navigation;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [timer, const SizedBox(height: 8), navigation],
          ),
        ),
      ),
    );
  }
}

class _CookingTimersBar extends StatelessWidget {
  const _CookingTimersBar({
    required this.timers,
    required this.onAddTimer,
    required this.onEditTimer,
    required this.onRemoveTimer,
  });

  final List<CookingTimer> timers;
  final VoidCallback onAddTimer;
  final void Function(CookingTimer timer) onEditTimer;
  final void Function(CookingTimer timer) onRemoveTimer;

  String formatDuration(Duration value) {
    final totalSeconds = value.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }

    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: timers.isEmpty
            ? InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onAddTimer,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.timer_outlined, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Ajouter un minuteur',
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final timer in timers) ...[
                      _CookingTimerChip(
                        timer: timer,
                        formattedDuration: formatDuration(
                          timer.remainingDuration,
                        ),
                        onTap: () {
                          onEditTimer(timer);
                        },
                        onRemove: () {
                          onRemoveTimer(timer);
                        },
                      ),
                      const SizedBox(width: 8),
                    ],
                    IconButton.filledTonal(
                      tooltip: 'Ajouter un minuteur',
                      onPressed: onAddTimer,
                      icon: const Icon(Icons.add),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _CookingTimerChip extends StatelessWidget {
  const _CookingTimerChip({
    required this.timer,
    required this.formattedDuration,
    required this.onTap,
    required this.onRemove,
  });

  final CookingTimer timer;
  final String formattedDuration;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: timer.hasFinished
          ? colorScheme.errorContainer
          : colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 118, maxWidth: 190),
          padding: const EdgeInsets.fromLTRB(10, 7, 4, 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: timer.hasFinished
                  ? colorScheme.error
                  : colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                timer.hasFinished ? Icons.alarm_on : Icons.timer_outlined,
                color: timer.hasFinished
                    ? colorScheme.error
                    : colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      timer.label.trim().isEmpty ? statusText : timer.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      formattedDuration,
                      style: TextStyle(
                        color: timer.hasFinished
                            ? colorScheme.error
                            : colorScheme.onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Réinitialiser',
                onPressed: onRemove,
                icon: const Icon(Icons.close),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get statusText {
    if (timer.isRunning) {
      return 'En cours';
    }

    if (timer.hasFinished) {
      return 'Terminé';
    }

    return 'Prêt';
  }
}

class _TimerSettings {
  const _TimerSettings({required this.duration, required this.label});

  final Duration duration;
  final String label;
}

class _TimerSettingsDialog extends StatefulWidget {
  const _TimerSettingsDialog({
    required this.initialDuration,
    required this.initialLabel,
  });

  final Duration initialDuration;
  final String initialLabel;

  @override
  State<_TimerSettingsDialog> createState() => _TimerSettingsDialogState();
}

class _TimerSettingsDialogState extends State<_TimerSettingsDialog> {
  late final TextEditingController minutesController;
  late final TextEditingController labelController;

  @override
  void initState() {
    super.initState();

    minutesController = TextEditingController(
      text: widget.initialDuration.inMinutes == 0
          ? ''
          : widget.initialDuration.inMinutes.toString(),
    );
    labelController = TextEditingController(text: widget.initialLabel);
  }

  @override
  void dispose() {
    minutesController.dispose();
    labelController.dispose();

    super.dispose();
  }

  void submit() {
    final minutes = int.tryParse(minutesController.text.trim()) ?? 0;

    Navigator.of(context).pop(
      _TimerSettings(
        duration: minutes <= 0 ? Duration.zero : Duration(minutes: minutes),
        label: labelController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Régler le minuteur'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: minutesController,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Temps',
              suffixText: 'min',
            ),
            onSubmitted: (_) {
              submit();
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: labelController,
            decoration: const InputDecoration(
              labelText: 'Libellé',
              hintText: 'Ex : Cuisson des pâtes',
            ),
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
        FilledButton(onPressed: submit, child: const Text('Valider')),
      ],
    );
  }
}

class _CookingNavigation extends StatelessWidget {
  const _CookingNavigation({
    required this.canGoPrevious,
    required this.isLastStep,
    required this.onPrevious,
    required this.onNext,
  });

  final bool canGoPrevious;
  final bool isLastStep;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: canGoPrevious ? onPrevious : null,
            icon: const Icon(Icons.arrow_back),
            label: const Text('Précédent'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.icon(
            onPressed: onNext,
            icon: Icon(isLastStep ? Icons.check : Icons.arrow_forward),
            label: Text(isLastStep ? 'Terminer' : 'Suivant'),
          ),
        ),
      ],
    );
  }
}

class _NoStepsCard extends StatelessWidget {
  const _NoStepsCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Text(
          'Cette recette ne contient pas encore d’étapes de préparation.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
