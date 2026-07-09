const String defaultRecipeEmoji = '🍽️';

class RecipeEmojiCategory {
  const RecipeEmojiCategory({required this.label, required this.emojis});

  final String label;
  final List<String> emojis;
}

const List<RecipeEmojiCategory> recipeEmojiCategories = [
  RecipeEmojiCategory(
    label: 'Général',
    emojis: ['🍽️', '🥘', '🍲', '🍛', '🍜', '🥣', '🫕', '🍱', '🥡', '🧂'],
  ),
  RecipeEmojiCategory(
    label: 'Pâtes, riz & féculents',
    emojis: [
      '🍝',
      '🍚',
      '🍙',
      '🍘',
      '🍞',
      '🥖',
      '🥐',
      '🥨',
      '🥯',
      '🫓',
      '🥔',
      '🍠',
    ],
  ),
  RecipeEmojiCategory(
    label: 'Plats rapides',
    emojis: [
      '🍕',
      '🍔',
      '🌭',
      '🥪',
      '🌮',
      '🌯',
      '🥙',
      '🧆',
      '🍟',
      '🥟',
      '🍢',
      '🍡',
    ],
  ),
  RecipeEmojiCategory(
    label: 'Fromages & produits laitiers',
    emojis: ['🧀', '🥛', '🧈', '🫕', '🍦', '🍨'],
  ),
  RecipeEmojiCategory(
    label: 'Viandes & œufs',
    emojis: ['🍗', '🍖', '🥩', '🥓', '🌭', '🍔', '🍳', '🥚'],
  ),
  RecipeEmojiCategory(
    label: 'Poissons & fruits de mer',
    emojis: ['🐟', '🍣', '🍤', '🦐', '🦞', '🦀', '🦪', '🐙', '🦑'],
  ),
  RecipeEmojiCategory(
    label: 'Légumes & salades',
    emojis: [
      '🥗',
      '🥦',
      '🥕',
      '🍅',
      '🥒',
      '🌽',
      '🫑',
      '🍆',
      '🥬',
      '🧅',
      '🧄',
      '🍄',
      '🥑',
      '🫛',
      '🫒',
    ],
  ),
  RecipeEmojiCategory(
    label: 'Fruits',
    emojis: [
      '🍎',
      '🍏',
      '🍐',
      '🍊',
      '🍋',
      '🍋‍🟩',
      '🍌',
      '🍉',
      '🍇',
      '🍓',
      '🫐',
      '🍒',
      '🍑',
      '🥭',
      '🍍',
      '🥝',
      '🥥',
      '🥑',
    ],
  ),
  RecipeEmojiCategory(
    label: 'Petit-déjeuner',
    emojis: [
      '🥞',
      '🧇',
      '🥐',
      '🥯',
      '🍞',
      '🥖',
      '🍳',
      '🥚',
      '🥣',
      '☕',
      '🍵',
      '🥛',
      '🍯',
    ],
  ),
  RecipeEmojiCategory(
    label: 'Desserts & sucré',
    emojis: [
      '🍰',
      '🎂',
      '🧁',
      '🥧',
      '🍪',
      '🍩',
      '🍫',
      '🍬',
      '🍭',
      '🍮',
      '🍯',
      '🍨',
      '🍦',
      '🧇',
    ],
  ),
  RecipeEmojiCategory(
    label: 'Boissons',
    emojis: [
      '☕',
      '🍵',
      '🥤',
      '🧃',
      '🧋',
      '🥛',
      '🍹',
      '🍸',
      '🍷',
      '🍺',
      '🍻',
      '🥂',
    ],
  ),
  RecipeEmojiCategory(
    label: 'Cuisine du monde',
    emojis: [
      '🍣',
      '🍤',
      '🍜',
      '🍥',
      '🍙',
      '🍚',
      '🍛',
      '🥟',
      '🥠',
      '🥡',
      '🌮',
      '🌯',
      '🥙',
      '🧆',
      '🥘',
      '🫔',
    ],
  ),
];

List<String> get recipeEmojiOptions {
  return recipeEmojiCategories
      .expand((category) => category.emojis)
      .toSet()
      .toList();
}
