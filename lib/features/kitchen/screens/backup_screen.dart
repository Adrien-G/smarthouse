import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../controllers/cuisine_controller.dart';
import '../services/backup_service.dart';
import 'local_sync_screen.dart';
import '../services/storage_service.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({
    super.key,
    required this.appData,
    required this.getAppData,
    required this.onRestoreData,
    required this.onMergeData,
  });

  final AppData appData;
  final AppData Function() getAppData;
  final Future<void> Function(AppData appData) onRestoreData;
  final Future<MergeBackupResult> Function(
    AppData appData, {
    MergePlanningMode planningMode,
  })
  onMergeData;

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool isExporting = false;
  bool isImporting = false;

  Future<void> exportBackup() async {
    if (isExporting) {
      return;
    }

    setState(() {
      isExporting = true;
    });

    try {
      final backupJson = BackupService.createBackupJson(widget.appData);
      final temporaryDirectory = await getTemporaryDirectory();
      final fileName = BackupService.buildBackupFileName();
      final file = File('${temporaryDirectory.path}/$fileName');

      await file.writeAsString(backupJson);

      await SharePlus.instance.share(
        ShareParams(
          text: 'Sauvegarde de mes recettes Cuisine',
          subject: 'Sauvegarde Cuisine',
          files: [XFile(file.path)],
        ),
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sauvegarde exportée.')));
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d’exporter la sauvegarde.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          isExporting = false;
        });
      }
    }
  }

  Future<void> importBackup() async {
    if (isImporting) {
      return;
    }

    setState(() {
      isImporting = true;
    });

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final pickedFile = result.files.single;

      final bytes =
          pickedFile.bytes ?? await File(pickedFile.path!).readAsBytes();

      final rawJson = utf8.decode(bytes);
      final importedData = BackupService.parseBackupJson(rawJson);

      if (!mounted) {
        return;
      }

      final importMode = await confirmImport(importedData);

      if (importMode == null) {
        return;
      }

      MergeBackupResult? mergeResult;

      switch (importMode) {
        case _BackupImportMode.merge:
          mergeResult = await widget.onMergeData(importedData);
        case _BackupImportMode.replace:
          await widget.onRestoreData(importedData);
      }

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            importMode == _BackupImportMode.merge
                ? buildMergeSummary(mergeResult)
                : 'Sauvegarde importée : ${importedData.recipes.length} recette(s).',
          ),
        ),
      );

      Navigator.of(context).pop();
    } on BackupException catch (error) {
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
          content: Text('Impossible d’importer cette sauvegarde.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isImporting = false;
        });
      }
    }
  }

  String buildMergeSummary(MergeBackupResult? result) {
    if (result == null || !result.hasChanges) {
      return 'Aucune nouveauté à fusionner.';
    }

    return 'Fusion terminée : ${result.addedRecipesCount} recette(s) ajoutée(s), '
        '${result.updatedRecipesCount} mise(s) à jour, '
        '${result.addedPlanningEntriesCount} repas planifié(s).';
  }

  void openLocalSyncScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) {
          return LocalSyncScreen(
            getAppData: widget.getAppData,
            onMergeData: widget.onMergeData,
          );
        },
      ),
    );
  }

  Future<_BackupImportMode?> confirmImport(AppData importedData) {
    return showDialog<_BackupImportMode>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Importer cette sauvegarde ?'),
          content: Text(
            'Cette sauvegarde contient :\n\n'
            '- ${importedData.recipes.length} recette(s)\n'
            '- ${importedData.weeklyPlanning.length} repas planifié(s)\n'
            '- ${importedData.checkedShoppingItems.length} article(s) coché(s)\n'
            '- ${importedData.pantryIngredientNames.length} ingrédient(s) de stock maison\n'
            '- ${importedData.mealHistoryEntries.length} repas dans l’historique\n\n'
            'Tu peux fusionner les recettes avec tes données actuelles ou tout remplacer.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Annuler'),
            ),
            OutlinedButton(
              onPressed: () {
                Navigator.of(context).pop(_BackupImportMode.replace);
              },
              child: const Text('Remplacer'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(_BackupImportMode.merge);
              },
              child: const Text('Fusionner'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final recipesCount = widget.appData.recipes.length;
    final planningCount = widget.appData.weeklyPlanning.length;
    final pantryIngredientCount = widget.appData.pantryIngredientNames.length;
    final mealHistoryCount = widget.appData.mealHistoryEntries.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Sauvegarde')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _BackupHeader(),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Données actuelles',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text('$recipesCount recette(s) enregistrée(s)'),
                  Text('$planningCount repas planifié(s)'),
                  Text('$pantryIngredientCount ingrédient(s) de stock maison'),
                  Text('$mealHistoryCount repas dans l’historique'),
                ],
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: const Text('Exporter mes données'),
              subtitle: const Text(
                'Créer un fichier JSON à conserver ou partager.',
              ),
              trailing: isExporting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: isExporting ? null : exportBackup,
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('Importer une sauvegarde'),
              subtitle: const Text(
                'Restaurer un fichier JSON exporté précédemment.',
              ),
              trailing: isImporting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: isImporting ? null : importBackup,
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.sync_alt_outlined),
              title: const Text('Synchroniser en Wi-Fi'),
              subtitle: const Text(
                'Échanger les recettes avec un autre appareil via QR code.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: openLocalSyncScreen,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Conseil : conserve une copie de ta sauvegarde hors du téléphone, par exemple dans Drive, par mail ou sur ton ordinateur.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _BackupHeader extends StatelessWidget {
  const _BackupHeader();

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
              Icons.backup_outlined,
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
                  'Sauvegarder mes recettes',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onPrimaryContainer,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Exporte un fichier JSON pour éviter de perdre tes données.',
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

enum _BackupImportMode { merge, replace }
