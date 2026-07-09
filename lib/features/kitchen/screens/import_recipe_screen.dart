import 'package:flutter/material.dart';

import '../services/recipe_text_parser.dart';

class ImportRecipeScreen extends StatefulWidget {
  const ImportRecipeScreen({super.key});

  @override
  State<ImportRecipeScreen> createState() => _ImportRecipeScreenState();
}

class _ImportRecipeScreenState extends State<ImportRecipeScreen> {
  final formKey = GlobalKey<FormState>();

  final nameController = TextEditingController();
  final recipeTextController = TextEditingController();
  final stepsController = TextEditingController();

  @override
  void dispose() {
    nameController.dispose();
    recipeTextController.dispose();
    stepsController.dispose();
    super.dispose();
  }

  void importRecipe() {
    final isValid = formKey.currentState?.validate() ?? false;

    if (!isValid) {
      return;
    }

    final parsedRecipe = RecipeTextParser.parse(
      rawText: recipeTextController.text,
      forcedName: nameController.text.trim().isEmpty
          ? null
          : nameController.text.trim(),
      forcedSteps: stepsController.text.trim().isEmpty
          ? null
          : stepsController.text.trim(),
    );

    Navigator.of(context).pop(parsedRecipe);
  }

  void insertExample() {
    recipeTextController.text =
        '''
Pâtes au pesto

Ingrédients :
- 250 g de pâtes
- 2 c. à soupe de pesto
- 50 g de parmesan

Préparation :
Faire cuire les pâtes.
Ajouter le pesto.
Servir avec le parmesan.
'''
            .trim();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Coller une recette'),
        actions: [
          IconButton(
            tooltip: 'Pré-remplir',
            onPressed: importRecipe,
            icon: const Icon(Icons.auto_fix_high_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const _ImportHeader(),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Mode recette rapide',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tu peux remplir le nom, coller seulement des ingrédients, puis ajouter une préparation courte.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Nom de la recette',
                          hintText: 'Ex : Pâtes au pesto',
                          prefixIcon: Icon(Icons.restaurant_menu),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: stepsController,
                        decoration: const InputDecoration(
                          labelText: 'Préparation rapide',
                          hintText: 'Optionnel',
                          prefixIcon: Icon(Icons.notes_outlined),
                          alignLabelWithHint: true,
                        ),
                        minLines: 3,
                        maxLines: 6,
                      ),
                    ],
                  ),
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Texte à analyser',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Colle une recette complète ou simplement une liste d’ingrédients. Tu pourras corriger avant d’enregistrer.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: recipeTextController,
                        decoration: const InputDecoration(
                          labelText: 'Recette ou ingrédients',
                          hintText:
                              'Ex : 250 g de pâtes\n2 c. à soupe de pesto\n50 g de parmesan',
                          prefixIcon: Icon(Icons.content_paste_outlined),
                          alignLabelWithHint: true,
                        ),
                        minLines: 12,
                        maxLines: 20,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Colle une recette ou quelques ingrédients.';
                          }

                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: insertExample,
                        icon: const Icon(Icons.lightbulb_outline),
                        label: const Text('Insérer un exemple'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: importRecipe,
                icon: const Icon(Icons.auto_fix_high_outlined),
                label: const Text('Pré-remplir la recette'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImportHeader extends StatelessWidget {
  const _ImportHeader();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              Icons.auto_fix_high_outlined,
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
                  'Ajout intelligent',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onPrimaryContainer,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Colle une recette ou une liste d’ingrédients, puis corrige le résultat.',
                  style: TextStyle(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w500,
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
