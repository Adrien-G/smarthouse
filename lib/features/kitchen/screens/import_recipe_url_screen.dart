import 'package:flutter/material.dart';

import '../services/recipe_url_importer.dart';

class ImportRecipeUrlScreen extends StatefulWidget {
  const ImportRecipeUrlScreen({super.key});

  @override
  State<ImportRecipeUrlScreen> createState() => _ImportRecipeUrlScreenState();
}

class _ImportRecipeUrlScreenState extends State<ImportRecipeUrlScreen> {
  final formKey = GlobalKey<FormState>();
  final urlController = TextEditingController();

  bool isLoading = false;

  @override
  void dispose() {
    urlController.dispose();
    super.dispose();
  }

  Future<void> importRecipe() async {
    final isValid = formKey.currentState?.validate() ?? false;

    if (!isValid || isLoading) {
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final recipe = await RecipeUrlImporter.importFromUrl(urlController.text);

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(recipe);
    } on RecipeUrlImportException catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Impossible d’importer cette recette. Tu peux essayer le mode “Coller une recette”.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  void insertExampleUrl() {
    urlController.text = 'https://example.com/recette';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Importer depuis un lien'),
        actions: [
          IconButton(
            tooltip: 'Importer',
            onPressed: isLoading ? null : importRecipe,
            icon: const Icon(Icons.download_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const _ImportUrlHeader(),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Lien de la recette',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Colle le lien d’une page de recette. Si le site expose une recette structurée, l’app pré-remplira le formulaire.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: urlController,
                        decoration: const InputDecoration(
                          labelText: 'URL',
                          hintText: 'https://...',
                          prefixIcon: Icon(Icons.link),
                        ),
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) async {
                          await importRecipe();
                        },
                        validator: (value) {
                          final url = value?.trim() ?? '';

                          if (url.isEmpty) {
                            return 'Colle un lien de recette.';
                          }

                          final uri = Uri.tryParse(url);

                          if (uri == null ||
                              !uri.hasScheme ||
                              !uri.hasAuthority) {
                            return 'Lien invalide.';
                          }

                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: isLoading ? null : importRecipe,
                icon: isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_outlined),
                label: Text(
                  isLoading ? 'Import en cours...' : 'Importer la recette',
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Si l’import ne fonctionne pas, utilise “Coller une recette” : certains sites ne fournissent pas de données structurées ou bloquent les requêtes.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImportUrlHeader extends StatelessWidget {
  const _ImportUrlHeader();

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
            child: Icon(Icons.link, color: colorScheme.primary, size: 30),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Import depuis URL',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onPrimaryContainer,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Récupère automatiquement les infos quand le site le permet.',
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
