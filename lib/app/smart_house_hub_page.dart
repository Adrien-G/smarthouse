import 'package:flutter/material.dart';

class SmartHouseHubPage extends StatelessWidget {
  const SmartHouseHubPage({
    super.key,
    required this.onOpenElectricity,
    required this.onOpenKitchen,
    required this.onOpenTransport,
    required this.onOpenSettings,
  });

  final VoidCallback onOpenElectricity;
  final VoidCallback onOpenKitchen;
  final VoidCallback onOpenTransport;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 720;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 16 : 28,
            vertical: 22,
          ),
          children: [
            const _HubHeader(),
            const SizedBox(height: 22),
            LayoutBuilder(
              builder: (context, constraints) {
                const spacing = 12.0;
                final columns = constraints.maxWidth >= 960
                    ? 3
                    : constraints.maxWidth >= 640
                    ? 2
                    : 1;
                final cardWidth =
                    (constraints.maxWidth - spacing * (columns - 1)) / columns;
                final cards = [
                  _FeatureCard(
                    icon: Icons.bolt,
                    title: 'Électricité',
                    subtitle: 'Linky, instantané et historique',
                    color: const Color(0xff1f7a5c),
                    onTap: onOpenElectricity,
                  ),
                  _FeatureCard(
                    icon: Icons.restaurant,
                    title: 'Cuisine',
                    subtitle: 'Recettes, planning et courses',
                    color: const Color(0xff9a5b13),
                    onTap: onOpenKitchen,
                  ),
                  _FeatureCard(
                    icon: Icons.directions_bus,
                    title: 'Transport',
                    subtitle: 'TER et bus',
                    color: const Color(0xff2563eb),
                    onTap: onOpenTransport,
                  ),
                  const _FeatureCard(
                    icon: Icons.device_thermostat,
                    title: 'Confort intérieur',
                    subtitle: 'Température et humidité des pièces',
                    color: Color(0xff7c3aed),
                  ),
                  _FeatureCard(
                    icon: Icons.settings,
                    title: 'Paramètres',
                    subtitle: 'Configuration globale',
                    color: const Color(0xff475569),
                    onTap: onOpenSettings,
                  ),
                ];

                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    for (final card in cards)
                      SizedBox(width: cardWidth, child: card),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _HubHeader extends StatelessWidget {
  const _HubHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SmartHouse',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Maison',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onTap != null;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xffe1e5dc)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: color.withValues(alpha: enabled ? 0.14 : 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(icon, color: enabled ? color : Colors.grey),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                enabled ? Icons.chevron_right : Icons.lock_outline,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
