class PreparationStepSuggestion {
  const PreparationStepSuggestion({required this.text});

  final String text;
}

class PreparationStepAnalyzer {
  static List<PreparationStepSuggestion> findImplicitPreparations({
    required Iterable<String> ingredientNames,
    required Iterable<String> steps,
  }) {
    final stepTexts = steps
        .map((step) => step.trim())
        .where((step) => step.isNotEmpty)
        .toList();
    final allStepsText = normalize(stepTexts.join(' '));
    final suggestions = <String>{};

    for (final ingredientName in ingredientNames) {
      final cleanedName = ingredientName.trim();

      if (cleanedName.isEmpty) {
        continue;
      }

      final normalizedIngredient = normalize(cleanedName);

      for (final step in stepTexts) {
        final normalizedStep = normalize(step);

        if (!containsIngredientTerm(normalizedStep, normalizedIngredient)) {
          continue;
        }

        for (final rule in _preparationRules) {
          if (hasExistingPreparation(
            allStepsText: allStepsText,
            normalizedIngredient: normalizedIngredient,
            actionTerms: rule.actionTerms,
          )) {
            continue;
          }

          final match = rule.pattern.firstMatch(normalizedStep);

          if (match == null) {
            continue;
          }

          final detail = cleanDetail(getOptionalNamedGroup(match, 'detail'));
          suggestions.add(
            buildSuggestionText(
              actionLabel: rule.actionLabel,
              ingredientName: cleanedName,
              detail: detail,
            ),
          );
        }
      }
    }

    if (allStepsText.contains('four prechauffe') &&
        !RegExp(r'\bprechauff\w*\b').hasMatch(allStepsText)) {
      suggestions.add('Préchauffer le four');
    }

    return suggestions
        .map((text) => PreparationStepSuggestion(text: text))
        .toList();
  }

  static String buildPreparationStep(List<PreparationStepSuggestion> items) {
    final lines = items.map((item) => '- ${item.text}').join('\n');

    return 'Préparations préalables :\n$lines';
  }

  static bool containsIngredientTerm(String text, String ingredient) {
    return RegExp('(^| )${RegExp.escape(ingredient)}( |s|x|\$)').hasMatch(text);
  }

  static bool hasExistingPreparation({
    required String allStepsText,
    required String normalizedIngredient,
    required List<String> actionTerms,
  }) {
    for (final actionTerm in actionTerms) {
      if (RegExp(
        '\\b$actionTerm\\b.{0,40}\\b${RegExp.escape(normalizedIngredient)}( |s|x|\$)',
      ).hasMatch(allStepsText)) {
        return true;
      }

      if (RegExp(
        '\\b${RegExp.escape(normalizedIngredient)}( |s|x|\$).{0,40}\\b$actionTerm\\b',
      ).hasMatch(allStepsText)) {
        return true;
      }
    }

    return false;
  }

  static String buildSuggestionText({
    required String actionLabel,
    required String ingredientName,
    required String detail,
  }) {
    final buffer = StringBuffer()
      ..write(actionLabel)
      ..write(' ')
      ..write(withArticle(ingredientName));

    if (detail.isNotEmpty) {
      buffer
        ..write(' ')
        ..write(detail);
    }

    return buffer.toString();
  }

  static String cleanDetail(String value) {
    var detail = value.trim();

    if (detail.isEmpty) {
      return '';
    }

    detail = detail
        .split(RegExp(r'\b(?:dans|avec|puis|et|avant|apres)\b'))
        .first
        .trim();

    return detail;
  }

  static String getOptionalNamedGroup(RegExpMatch match, String name) {
    try {
      return match.namedGroup(name) ?? '';
    } on ArgumentError {
      return '';
    }
  }

  static String withArticle(String ingredientName) {
    final trimmedName = ingredientName.trim();
    final normalizedName = normalize(trimmedName);

    if (normalizedName.startsWith(RegExp(r'[aeiouh]'))) {
      return "l’$trimmedName";
    }

    if (normalizedName.endsWith('s') || normalizedName.endsWith('x')) {
      return 'les $trimmedName';
    }

    return 'le $trimmedName';
  }

  static String normalize(String value) {
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

    return buffer
        .toString()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

class _PreparationRule {
  const _PreparationRule({
    required this.pattern,
    required this.actionLabel,
    required this.actionTerms,
  });

  final RegExp pattern;
  final String actionLabel;
  final List<String> actionTerms;
}

final _preparationRules = [
  _PreparationRule(
    pattern: RegExp(r'\bcoupe\w*\b(?: (?<detail>en [a-z0-9 ]{3,32}))?'),
    actionLabel: 'Couper',
    actionTerms: ['couper', 'coupez', 'decouper', 'decoupez', 'tailler'],
  ),
  _PreparationRule(
    pattern: RegExp(r'\bemince\w*\b'),
    actionLabel: 'Émincer',
    actionTerms: ['emincer', 'emincez'],
  ),
  _PreparationRule(
    pattern: RegExp(r'\bhache\w*\b'),
    actionLabel: 'Hacher',
    actionTerms: ['hacher', 'hachez'],
  ),
  _PreparationRule(
    pattern: RegExp(r'\brape\w*\b'),
    actionLabel: 'Râper',
    actionTerms: ['raper', 'rapez'],
  ),
  _PreparationRule(
    pattern: RegExp(r'\begoutte\w*\b'),
    actionLabel: 'Égoutter',
    actionTerms: ['egoutter', 'egouttez'],
  ),
  _PreparationRule(
    pattern: RegExp(r'\bfondu\w*\b'),
    actionLabel: 'Faire fondre',
    actionTerms: ['fondre', 'fondu'],
  ),
];
