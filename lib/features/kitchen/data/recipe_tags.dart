class RecipeTagGroup {
  const RecipeTagGroup({required this.label, required this.tags});

  final String label;
  final List<String> tags;
}

const List<String> cookingModeTags = [
  'Four',
  'Plaque de cuisson',
  'Sans cuisson',
];

const String reusablePreparationTag = 'Préparation réutilisable';

const List<String> recipeTypeTags = [
  'Entrée',
  'Plat principal',
  'Plat complet',
  'Accompagnement',
  'Dessert',
  reusablePreparationTag,
];

const List<RecipeTagGroup> recipeTagGroups = [
  RecipeTagGroup(label: 'Mode de préparation', tags: cookingModeTags),
  RecipeTagGroup(label: 'Type de recette', tags: recipeTypeTags),
];

List<String> get recipeTags {
  return recipeTagGroups.expand((group) => group.tags).toList();
}
