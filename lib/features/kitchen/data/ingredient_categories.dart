const String defaultIngredientCategory = 'Autre';

const List<String> ingredientCategories = [
  'Fruits & légumes',
  'Frais',
  'Épicerie',
  'Viandes / poissons',
  'Surgelés',
  'Boissons',
  'Hygiène / entretien',
  'Autre',
];

int getIngredientCategoryOrder(String category) {
  final index = ingredientCategories.indexOf(category);

  if (index == -1) {
    return ingredientCategories.length;
  }

  return index;
}
