import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../controllers/cuisine_controller.dart';
import '../services/backup_service.dart';
import '../services/storage_service.dart';

enum _LocalSyncMode { bidirectional, sendOnly }

class _LocalSyncPayload {
  const _LocalSyncPayload({required this.url, required this.mode});

  final String url;
  final _LocalSyncMode mode;
}

class LocalSyncScreen extends StatefulWidget {
  const LocalSyncScreen({
    super.key,
    required this.getAppData,
    required this.onMergeData,
  });

  final AppData Function() getAppData;
  final Future<MergeBackupResult> Function(
    AppData appData, {
    MergePlanningMode planningMode,
  })
  onMergeData;

  @override
  State<LocalSyncScreen> createState() => _LocalSyncScreenState();
}

class _LocalSyncScreenState extends State<LocalSyncScreen> {
  HttpServer? syncServer;
  String? syncUrl;
  String statusText = 'Prêt à synchroniser.';
  MergeBackupResult? lastMergeResult;
  bool isStartingHost = false;
  bool isJoining = false;
  _LocalSyncMode syncMode = _LocalSyncMode.bidirectional;

  @override
  void dispose() {
    final server = syncServer;
    syncServer = null;
    syncUrl = null;
    server?.close(force: true);
    super.dispose();
  }

  Future<void> startHosting() async {
    if (syncServer != null || isStartingHost) {
      return;
    }

    setState(() {
      isStartingHost = true;
      statusText = 'Préparation de la synchro locale...';
    });

    try {
      final localIpAddress = await findLocalIpAddress();
      final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);

      syncServer = server;
      syncUrl = 'http://$localIpAddress:${server.port}/sync';

      server.listen(handleSyncRequest);

      setState(() {
        statusText = 'QR code prêt. L’autre appareil peut le scanner.';
      });
    } catch (_) {
      setState(() {
        statusText =
            'Impossible de démarrer la synchro. Vérifie que le Wi-Fi est actif.';
      });
    } finally {
      if (mounted) {
        setState(() {
          isStartingHost = false;
        });
      }
    }
  }

  Future<void> stopHosting() async {
    final server = syncServer;

    if (server == null) {
      return;
    }

    syncServer = null;
    syncUrl = null;
    await server.close(force: true);

    if (!mounted) {
      return;
    }

    setState(() {
      statusText = 'Synchro arrêtée.';
    });
  }

  Future<String> findLocalIpAddress() async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );

    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (!address.isLoopback && !address.address.startsWith('169.254.')) {
          return address.address;
        }
      }
    }

    throw const SocketException('Aucune adresse locale trouvée.');
  }

  Future<void> handleSyncRequest(HttpRequest request) async {
    if (request.method != 'POST' || request.uri.path != '/sync') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    try {
      final rawJson = await utf8.decoder.bind(request).join();
      final importedData = BackupService.parseBackupJson(rawJson);
      final mergeResult = syncMode == _LocalSyncMode.bidirectional
          ? await widget.onMergeData(importedData)
          : null;
      final responseJson = BackupService.createBackupJson(widget.getAppData());

      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType.json;
      request.response.write(responseJson);
      await request.response.close();

      if (!mounted) {
        return;
      }

      setState(() {
        lastMergeResult = mergeResult;
        statusText = syncMode == _LocalSyncMode.bidirectional
            ? 'Synchro reçue et fusionnée.'
            : 'Données envoyées sans importer l’autre appareil.';
      });
    } catch (_) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();

      if (!mounted) {
        return;
      }

      setState(() {
        statusText = 'Synchro reçue, mais le fichier était invalide.';
      });
    }
  }

  Future<void> scanAndJoinSync() async {
    final payload = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) {
          return const _LocalSyncQrScannerScreen();
        },
      ),
    );

    if (payload == null || payload.trim().isEmpty) {
      return;
    }

    await joinSync(payload);
  }

  Future<void> joinSync(String payload) async {
    if (isJoining) {
      return;
    }

    setState(() {
      isJoining = true;
      statusText = 'Connexion à l’autre appareil...';
    });

    try {
      final syncPayload = parseSyncPayload(payload);
      final backupJson = BackupService.createBackupJson(widget.getAppData());
      final response = await http
          .post(
            Uri.parse(syncPayload.url),
            headers: {'content-type': 'application/json; charset=utf-8'},
            body: backupJson,
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != HttpStatus.ok) {
        throw const FormatException('Réponse invalide.');
      }

      final hostData = BackupService.parseBackupJson(response.body);
      final mergeResult = await widget.onMergeData(
        hostData,
        planningMode: syncPayload.mode == _LocalSyncMode.sendOnly
            ? MergePlanningMode.replace
            : MergePlanningMode.fillEmptySlots,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        lastMergeResult = mergeResult;
        statusText = 'Synchro terminée.';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        statusText =
            'Impossible de synchroniser. Vérifie que les deux appareils sont sur le même Wi-Fi.';
      });
    } finally {
      if (mounted) {
        setState(() {
          isJoining = false;
        });
      }
    }
  }

  _LocalSyncPayload parseSyncPayload(String payload) {
    final trimmedPayload = payload.trim();

    if (trimmedPayload.startsWith('http://')) {
      return _LocalSyncPayload(
        url: trimmedPayload,
        mode: _LocalSyncMode.bidirectional,
      );
    }

    final decoded = jsonDecode(trimmedPayload);

    if (decoded is! Map || decoded['type'] != 'cuisine_local_sync') {
      throw const FormatException('QR code invalide.');
    }

    final rawMode = decoded['mode'] as String?;
    final mode = rawMode == _LocalSyncMode.sendOnly.name
        ? _LocalSyncMode.sendOnly
        : _LocalSyncMode.bidirectional;

    return _LocalSyncPayload(url: decoded['url'] as String, mode: mode);
  }

  String buildQrPayload() {
    return jsonEncode({
      'type': 'cuisine_local_sync',
      'version': 1,
      'mode': syncMode.name,
      'url': syncUrl,
    });
  }

  String buildMergeSummary() {
    final result = lastMergeResult;

    if (result == null) {
      return statusText;
    }

    if (!result.hasChanges) {
      return '$statusText Aucune nouveauté à fusionner.';
    }

    return '$statusText ${result.addedRecipesCount} recette(s) ajoutée(s), '
        '${result.updatedRecipesCount} mise(s) à jour, '
        '${result.addedPlanningEntriesCount} repas planifié(s), '
        '${result.addedMealHistoryEntriesCount} repas historique(s).';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentSyncUrl = syncUrl;

    return Scaffold(
      appBar: AppBar(title: const Text('Synchro locale')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
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
                    Icons.sync_alt_outlined,
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
                        'Synchro Wi-Fi',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: colorScheme.onPrimaryContainer,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Les deux appareils doivent être sur le même réseau.',
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
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Créer une synchro',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'L’autre appareil scanne ce QR code pour échanger les recettes.',
                  ),
                  const SizedBox(height: 14),
                  SegmentedButton<_LocalSyncMode>(
                    segments: const [
                      ButtonSegment(
                        value: _LocalSyncMode.bidirectional,
                        label: Text('Échanger'),
                        icon: Icon(Icons.sync_alt_outlined),
                      ),
                      ButtonSegment(
                        value: _LocalSyncMode.sendOnly,
                        label: Text('Partager'),
                        icon: Icon(Icons.upload_outlined),
                      ),
                    ],
                    selected: {syncMode},
                    onSelectionChanged: currentSyncUrl == null
                        ? (values) {
                            setState(() {
                              syncMode = values.first;
                            });
                          }
                        : null,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    syncMode == _LocalSyncMode.bidirectional
                        ? 'Échange : les deux appareils fusionnent leurs nouveautés.'
                        : 'Partager : cet appareil envoie ses données sans importer celles de l’autre.',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  if (currentSyncUrl == null)
                    FilledButton.icon(
                      onPressed: isStartingHost ? null : startHosting,
                      icon: isStartingHost
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.qr_code_2),
                      label: const Text('Afficher un QR code'),
                    )
                  else ...[
                    Center(
                      child: QrImageView(
                        data: buildQrPayload(),
                        version: QrVersions.auto,
                        size: 220,
                        backgroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      currentSyncUrl,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: stopHosting,
                      icon: const Icon(Icons.close),
                      label: const Text('Arrêter la synchro'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: const Text('Rejoindre une synchro'),
              subtitle: const Text(
                'Scanner le QR code affiché sur l’autre appareil.',
              ),
              trailing: isJoining
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: isJoining ? null : scanAndJoinSync,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                buildMergeSummary(),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalSyncQrScannerScreen extends StatefulWidget {
  const _LocalSyncQrScannerScreen();

  @override
  State<_LocalSyncQrScannerScreen> createState() =>
      _LocalSyncQrScannerScreenState();
}

class _LocalSyncQrScannerScreenState extends State<_LocalSyncQrScannerScreen> {
  bool hasScanned = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scanner le QR code')),
      body: MobileScanner(
        onDetect: (capture) {
          if (hasScanned) {
            return;
          }

          final barcode = capture.barcodes.firstOrNull;
          final rawValue = barcode?.rawValue;

          if (rawValue == null || rawValue.trim().isEmpty) {
            return;
          }

          hasScanned = true;
          Navigator.of(context).pop(rawValue);
        },
      ),
    );
  }
}
