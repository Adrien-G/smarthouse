const String specialMealPrefix = 'special_meal|';
const String composedMealPrefix = 'composed_meal|';

const String defaultSpecialMealLabel = 'Repas à l’extérieur';

const List<String> quickSpecialMealLabels = [
  'Restaurant',
  'Repas à l’extérieur',
  'Invités',
  'Restes',
  'Pas de repas',
];

String buildSpecialMealValue(String label) {
  final cleanedLabel = label.trim();

  if (cleanedLabel.isEmpty) {
    return '$specialMealPrefix$defaultSpecialMealLabel';
  }

  return '$specialMealPrefix$cleanedLabel';
}

bool isSpecialMealValue(String? value) {
  return value != null && value.startsWith(specialMealPrefix);
}

String getSpecialMealLabel(String value) {
  if (!isSpecialMealValue(value)) {
    return '';
  }

  final label = value.substring(specialMealPrefix.length).trim();

  if (label.isEmpty) {
    return defaultSpecialMealLabel;
  }

  return label;
}

String buildRecipePlanningValue({
  required String recipeId,
  String? accompanimentRecipeId,
}) {
  final cleanedAccompanimentId = accompanimentRecipeId?.trim();

  if (cleanedAccompanimentId == null || cleanedAccompanimentId.isEmpty) {
    return recipeId;
  }

  return '$composedMealPrefix$recipeId|$cleanedAccompanimentId';
}

bool isComposedMealValue(String? value) {
  return value != null && value.startsWith(composedMealPrefix);
}

String? getMainRecipeIdFromPlanningValue(String? value) {
  if (value == null || value.trim().isEmpty || isSpecialMealValue(value)) {
    return null;
  }

  if (!isComposedMealValue(value)) {
    return value;
  }

  final content = value.substring(composedMealPrefix.length);
  final parts = content.split('|');

  if (parts.isEmpty || parts.first.trim().isEmpty) {
    return null;
  }

  return parts.first.trim();
}

String? getAccompanimentRecipeIdFromPlanningValue(String? value) {
  if (value == null || !isComposedMealValue(value)) {
    return null;
  }

  final content = value.substring(composedMealPrefix.length);
  final parts = content.split('|');

  if (parts.length < 2 || parts[1].trim().isEmpty) {
    return null;
  }

  return parts[1].trim();
}

List<String> getRecipeIdsFromPlanningValue(String? value) {
  final recipeIds = <String>[];

  final mainRecipeId = getMainRecipeIdFromPlanningValue(value);
  final accompanimentRecipeId = getAccompanimentRecipeIdFromPlanningValue(
    value,
  );

  if (mainRecipeId != null) {
    recipeIds.add(mainRecipeId);
  }

  if (accompanimentRecipeId != null) {
    recipeIds.add(accompanimentRecipeId);
  }

  return recipeIds;
}

String removeAccompanimentFromPlanningValue(String value) {
  final mainRecipeId = getMainRecipeIdFromPlanningValue(value);

  if (mainRecipeId == null) {
    return value;
  }

  return buildRecipePlanningValue(recipeId: mainRecipeId);
}
