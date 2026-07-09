import '../data/ingredient_categories.dart';

class Ingredient {
  const Ingredient({
    required this.name,
    this.quantity,
    this.unit = '',
    this.category = defaultIngredientCategory,
    this.includeInShoppingList = true,
  });

  final String name;
  final double? quantity;
  final String unit;
  final String category;

  /// Si false, l’ingrédient apparaît dans la recette,
  /// mais il n’est pas ajouté à la liste de courses.
  final bool includeInShoppingList;

  Ingredient copyWith({
    String? name,
    double? quantity,
    String? unit,
    String? category,
    bool? includeInShoppingList,
  }) {
    return Ingredient(
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      category: category ?? this.category,
      includeInShoppingList:
          includeInShoppingList ?? this.includeInShoppingList,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'quantity': quantity,
      'unit': unit,
      'category': category,
      'includeInShoppingList': includeInShoppingList,
    };
  }

  factory Ingredient.fromJson(Map<String, dynamic> json) {
    return Ingredient(
      name: json['name'] as String? ?? '',
      quantity: json['quantity'] == null
          ? null
          : (json['quantity'] as num).toDouble(),
      unit: json['unit'] as String? ?? '',
      category: json['category'] as String? ?? defaultIngredientCategory,
      includeInShoppingList: json['includeInShoppingList'] as bool? ?? true,
    );
  }

  String get formattedQuantity {
    final value = quantity;

    if (value == null) {
      return '';
    }

    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }

    return value
        .toStringAsFixed(2)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '')
        .replaceAll('.', ',');
  }

  String get displayText {
    final parts = <String>[];

    if (quantity != null) {
      parts.add(formattedQuantity);
    }

    final cleanedUnit = unit.trim();
    final normalizedUnit = cleanedUnit.toLowerCase();

    final shouldShowUnit =
        cleanedUnit.isNotEmpty &&
        normalizedUnit != 'unité' &&
        normalizedUnit != 'unite';

    if (shouldShowUnit) {
      parts.add(cleanedUnit);
    }

    parts.add(name.trim());

    return parts.join(' ');
  }
}
