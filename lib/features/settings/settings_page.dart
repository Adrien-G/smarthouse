import 'package:flutter/material.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.navitiaApiKey,
    required this.onChangeNavitiaApiKey,
    required this.onBackToHub,
  });

  final String navitiaApiKey;
  final ValueChanged<String> onChangeNavitiaApiKey;
  final VoidCallback onBackToHub;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _navitiaController;
  var _hideKey = true;

  @override
  void initState() {
    super.initState();
    _navitiaController = TextEditingController(text: widget.navitiaApiKey);
  }

  @override
  void dispose() {
    _navitiaController.dispose();
    super.dispose();
  }

  void _save() {
    widget.onChangeNavitiaApiKey(_navitiaController.text.trim());
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Paramètre enregistré')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: widget.onBackToHub,
          tooltip: 'Accueil',
          icon: const Icon(Icons.home_outlined),
        ),
        title: const Text('Paramètres'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          children: [
            Text(
              'Configuration',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Réglages locaux stockés sur ce téléphone',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 18),
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xffe1e5dc)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.train, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          'Transports',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _navitiaController,
                      obscureText: _hideKey,
                      decoration: InputDecoration(
                        labelText: 'Clé API Navitia',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: _hideKey
                              ? 'Afficher la clé'
                              : 'Masquer la clé',
                          onPressed: () {
                            setState(() {
                              _hideKey = !_hideKey;
                            });
                          },
                          icon: Icon(
                            _hideKey
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Enregistrer'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
