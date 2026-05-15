import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class InlineStatusMessage extends StatelessWidget {
  const InlineStatusMessage({
    super.key,
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xfffffbeb),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xfffde68a)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: const Color(0xff92400e)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xff78350f),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EmptyHistoryMessage extends StatelessWidget {
  const EmptyHistoryMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xffe1e5dc)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            Icon(icon, size: 42, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 10),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 12), action!],
          ],
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.inverse = false,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;
  final bool inverse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = inverse ? Colors.white : theme.colorScheme.onSurface;
    final secondary = inverse
        ? Colors.white.withValues(alpha: 0.7)
        : theme.colorScheme.onSurfaceVariant;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(color: secondary),
              ),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 14),
          Text(message),
        ],
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    required this.apiBaseUrl,
    required this.error,
    required this.onRetry,
    required this.onChangeApiBaseUrl,
  });

  final String apiBaseUrl;
  final Object? error;
  final VoidCallback onRetry;
  final ValueChanged<String> onChangeApiBaseUrl;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 46),
            const SizedBox(height: 12),
            const Text(
              'Raspberry déconnecté',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Aucune donnée locale disponible. Appuie sur Réessayer pour interroger le Raspberry.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Adresse utilisée : $apiBaseUrl',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(
                error.toString(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => showApiBaseUrlDialog(
                context: context,
                currentValue: apiBaseUrl,
                onSubmitted: onChangeApiBaseUrl,
              ),
              icon: const Icon(Icons.settings),
              label: const Text("Changer l'adresse"),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showApiBaseUrlDialog({
  required BuildContext context,
  required String currentValue,
  required ValueChanged<String> onSubmitted,
}) async {
  final controller = TextEditingController(text: currentValue);

  final result = await showDialog<String>(
    context: context,
    builder: (context) {
      String? testMessage;
      var isTesting = false;

      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Adresse du Raspberry'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'URL API',
                    hintText: 'http://192.168.1.42:8080',
                  ),
                  autofocus: true,
                  onSubmitted: (value) => Navigator.of(context).pop(value),
                ),
                if (testMessage != null) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      testMessage!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Annuler'),
              ),
              OutlinedButton.icon(
                onPressed: isTesting
                    ? null
                    : () async {
                        setDialogState(() {
                          isTesting = true;
                          testMessage = 'Test en cours...';
                        });

                        final normalized = normalizeApiBaseUrlValue(
                          controller.text,
                        );
                        final message = await _testApiHealth(normalized);
                        setDialogState(() {
                          isTesting = false;
                          testMessage = message;
                        });
                      },
                icon: const Icon(Icons.wifi_find),
                label: const Text('Tester'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(controller.text),
                child: const Text('Enregistrer'),
              ),
            ],
          );
        },
      );
    },
  );

  controller.dispose();
  if (result == null || result.trim().isEmpty) {
    return;
  }
  onSubmitted(result);
}

String normalizeApiBaseUrlValue(String value) {
  final trimmed = value.trim();
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed.replaceFirst(RegExp(r'/+$'), '');
  }
  return 'http://${trimmed.replaceFirst(RegExp(r'/+$'), '')}';
}

Future<String> _testApiHealth(String baseUrl) async {
  try {
    final response = await http
        .get(Uri.parse('$baseUrl/api/health'))
        .timeout(const Duration(seconds: 3));
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return 'Connexion OK sur $baseUrl';
    }
    return 'API trouvée, mais HTTP ${response.statusCode} sur /api/health';
  } catch (error) {
    return 'Connexion impossible à $baseUrl/api/health';
  }
}

String formatTime(DateTime dateTime) {
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String formatDate(DateTime dateTime) {
  final day = dateTime.day.toString().padLeft(2, '0');
  final month = dateTime.month.toString().padLeft(2, '0');
  final year = dateTime.year.toString().padLeft(4, '0');
  return '$day/$month/$year';
}
