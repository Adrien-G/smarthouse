class MealHistoryEntry {
  const MealHistoryEntry({
    required this.id,
    required this.recipeId,
    required this.recipeName,
    required this.recipeEmoji,
    required this.slotId,
    required this.slotLabel,
    required this.cookedAt,
  });

  final String id;
  final String recipeId;
  final String recipeName;
  final String recipeEmoji;
  final String slotId;
  final String slotLabel;
  final DateTime cookedAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'recipeId': recipeId,
      'recipeName': recipeName,
      'recipeEmoji': recipeEmoji,
      'slotId': slotId,
      'slotLabel': slotLabel,
      'cookedAt': cookedAt.toIso8601String(),
    };
  }

  factory MealHistoryEntry.fromJson(Map<String, dynamic> json) {
    return MealHistoryEntry(
      id: json['id'] as String? ?? '',
      recipeId: json['recipeId'] as String? ?? '',
      recipeName: json['recipeName'] as String? ?? '',
      recipeEmoji: json['recipeEmoji'] as String? ?? '🍽️',
      slotId: json['slotId'] as String? ?? '',
      slotLabel: json['slotLabel'] as String? ?? '',
      cookedAt:
          DateTime.tryParse(json['cookedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
