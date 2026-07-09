class MealSlot {
  const MealSlot({required this.id, required this.day, required this.meal});

  final String id;
  final String day;
  final String meal;

  String get label => '$day $meal';
}

const List<String> mealSlotDays = [
  'Lundi',
  'Mardi',
  'Mercredi',
  'Jeudi',
  'Vendredi',
  'Samedi',
  'Dimanche',
];

const List<MealSlot> mealSlots = [
  MealSlot(id: 'lundi_midi', day: 'Lundi', meal: 'Midi'),
  MealSlot(id: 'lundi_soir', day: 'Lundi', meal: 'Soir'),
  MealSlot(id: 'mardi_midi', day: 'Mardi', meal: 'Midi'),
  MealSlot(id: 'mardi_soir', day: 'Mardi', meal: 'Soir'),
  MealSlot(id: 'mercredi_midi', day: 'Mercredi', meal: 'Midi'),
  MealSlot(id: 'mercredi_soir', day: 'Mercredi', meal: 'Soir'),
  MealSlot(id: 'jeudi_midi', day: 'Jeudi', meal: 'Midi'),
  MealSlot(id: 'jeudi_soir', day: 'Jeudi', meal: 'Soir'),
  MealSlot(id: 'vendredi_midi', day: 'Vendredi', meal: 'Midi'),
  MealSlot(id: 'vendredi_soir', day: 'Vendredi', meal: 'Soir'),
  MealSlot(id: 'samedi_midi', day: 'Samedi', meal: 'Midi'),
  MealSlot(id: 'samedi_soir', day: 'Samedi', meal: 'Soir'),
  MealSlot(id: 'dimanche_midi', day: 'Dimanche', meal: 'Midi'),
  MealSlot(id: 'dimanche_soir', day: 'Dimanche', meal: 'Soir'),
];

const Map<String, String> legacyDayToDinnerSlotId = {
  'Lundi': 'lundi_soir',
  'Mardi': 'mardi_soir',
  'Mercredi': 'mercredi_soir',
  'Jeudi': 'jeudi_soir',
  'Vendredi': 'vendredi_soir',
  'Samedi': 'samedi_soir',
  'Dimanche': 'dimanche_soir',
};

List<MealSlot> getMealSlotsForDay(String day) {
  return mealSlots.where((slot) => slot.day == day).toList();
}

String getMealSlotLabel(String slotId) {
  for (final slot in mealSlots) {
    if (slot.id == slotId) {
      return slot.label;
    }
  }

  return slotId;
}

Map<String, String> migrateLegacyPlanning(Map<String, String> savedPlanning) {
  final validSlotIds = mealSlots.map((slot) => slot.id).toSet();
  final migratedPlanning = <String, String>{};

  for (final entry in savedPlanning.entries) {
    if (validSlotIds.contains(entry.key)) {
      migratedPlanning[entry.key] = entry.value;
      continue;
    }

    final migratedSlotId = legacyDayToDinnerSlotId[entry.key];

    if (migratedSlotId != null) {
      migratedPlanning[migratedSlotId] = entry.value;
    }
  }

  return migratedPlanning;
}

bool containsLegacyPlanningKeys(Map<String, String> savedPlanning) {
  final validSlotIds = mealSlots.map((slot) => slot.id).toSet();

  return savedPlanning.keys.any((key) => !validSlotIds.contains(key));
}
