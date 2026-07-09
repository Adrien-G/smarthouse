import 'package:flutter/material.dart';

import 'data/navitia_transport_repository.dart';
import 'data/transport_config.dart';
import 'models/transport_models.dart';

class TransportsPage extends StatefulWidget {
  const TransportsPage({
    super.key,
    required this.navitiaApiKey,
    required this.onBackToHub,
    required this.onOpenSettings,
  });

  final String navitiaApiKey;
  final VoidCallback onBackToHub;
  final VoidCallback onOpenSettings;

  @override
  State<TransportsPage> createState() => _TransportsPageState();
}

class _TransportsPageState extends State<TransportsPage> {
  late final NavitiaTransportRepository _repository;
  late Future<List<TransportRouteDepartures>> _future;

  @override
  void initState() {
    super.initState();
    _repository = NavitiaTransportRepository(apiKey: widget.navitiaApiKey);
    _future = _load();
  }

  Future<List<TransportRouteDepartures>> _load() {
    return _repository.fetchRoutes(TransportConfig.routes);
  }

  void _refresh() {
    setState(() {
      _future = _load();
    });
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
        title: const Text('Transports'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<List<TransportRouteDepartures>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return _ErrorView(
                error: snapshot.error,
                onRetry: _refresh,
                onOpenSettings: widget.onOpenSettings,
              );
            }

            final data = snapshot.data ?? const [];
            final trains = data
                .where((item) => item.route.mode == TransportMode.train)
                .toList();
            final buses = data
                .where((item) => item.route.mode == TransportMode.bus)
                .toList();

            return RefreshIndicator(
              onRefresh: () async => _refresh(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                children: [
                  Text(
                    'Prochains passages',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Trajets fixes configurés dans SmartHouse',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _TransportSection(
                    title: 'Trains TER',
                    icon: Icons.train,
                    routes: trains,
                  ),
                  const SizedBox(height: 18),
                  _TransportSection(
                    title: 'Bus H',
                    icon: Icons.directions_bus,
                    routes: buses,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.error,
    required this.onRetry,
    required this.onOpenSettings,
  });

  final Object? error;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final missingKey = error is MissingNavitiaApiKeyException;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                missingKey ? Icons.key_off_outlined : Icons.cloud_off_outlined,
                size: 42,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(
                missingKey
                    ? 'Clé Navitia absente'
                    : 'Impossible de récupérer les transports',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                missingKey
                    ? 'Ajoute ta clé API dans le menu Paramètres.'
                    : error.toString(),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              if (missingKey)
                FilledButton.icon(
                  onPressed: onOpenSettings,
                  icon: const Icon(Icons.settings),
                  label: const Text('Ouvrir Paramètres'),
                )
              else
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Réessayer'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransportSection extends StatelessWidget {
  const _TransportSection({
    required this.title,
    required this.icon,
    required this.routes,
  });

  final String title;
  final IconData icon;
  final List<TransportRouteDepartures> routes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (final route in routes) ...[
          _RouteCard(routeDepartures: route),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({required this.routeDepartures});

  final TransportRouteDepartures routeDepartures;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final route = routeDepartures.route;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xffe1e5dc)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${route.fromLabel} → ${route.toLabel}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  route.title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (routeDepartures.hasError)
              Text(
                'Chargement impossible : ${routeDepartures.error}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              )
            else if (routeDepartures.departures.isEmpty)
              Text(
                'Aucun prochain passage trouvé.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              for (final departure in routeDepartures.departures)
                _DepartureRow(departure: departure),
          ],
        ),
      ),
    );
  }
}

class _DepartureRow extends StatelessWidget {
  const _DepartureRow({required this.departure});

  final TransportDeparture departure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final wait = departure.departure.difference(now);
    final waitLabel = wait.inMinutes <= 0
        ? 'Maintenant'
        : '${wait.inMinutes} min';
    final duration = departure.durationMinutes;
    final platform = departure.platformLabel;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 54,
            child: Text(
              _formatTime(departure.departure),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  departure.direction,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (duration != null)
                  Text(
                    platform == null
                        ? 'Trajet $duration min'
                        : 'Voie $platform · trajet $duration min',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (duration == null && platform != null)
                  Text(
                    'Voie $platform',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            waitLabel,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatTime(DateTime value) {
    return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  }
}
