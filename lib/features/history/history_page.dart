part of '../../main.dart';

enum HistoryRange { day, week }

class HistoryPage extends StatefulWidget {
  const HistoryPage({
    super.key,
    required this.apiBaseUrl,
    required this.repository,
  });

  final String apiBaseUrl;
  final LinkyRepository repository;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late LinkyRepository _repository;
  late Future<LinkySnapshot> _snapshotFuture;
  LinkyLoadState _loadState = const LinkyLoadState.connecting();
  var _range = HistoryRange.day;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _repository = widget.repository;
    _snapshotFuture = _loadSelectedDateFromCache();
  }

  void _reload() {
    setState(() {
      _snapshotFuture = _refreshSelectedDateFromNetwork();
    });
  }

  Future<LinkySnapshot> _loadSelectedDateFromCache() async {
    _updateLoadState(const LinkyLoadState.loadingPeriod('du cache local'));
    return _repository.fetchCachedDailySnapshot(_selectedDate);
  }

  Future<LinkySnapshot> _refreshSelectedDateFromNetwork() async {
    _updateLoadState(const LinkyLoadState.connecting());
    if (_repository is ApiLinkyRepository) {
      await (_repository as ApiLinkyRepository).checkHealth();
    }

    _updateLoadState(const LinkyLoadState.loadingPeriod('de la journée'));
    return _repository.fetchDailySnapshot(_selectedDate);
  }

  void _updateLoadState(LinkyLoadState state) {
    if (!mounted) {
      _loadState = state;
      return;
    }
    setState(() {
      _loadState = state;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked == null) {
      return;
    }

    setState(() {
      _selectedDate = picked;
      _snapshotFuture = _loadSelectedDateFromCache();
    });
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 720;

    return SafeArea(
      child: FutureBuilder<LinkySnapshot>(
        future: _snapshotFuture,
        builder: (context, snapshot) {
          return ListView(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 16 : 28,
              vertical: 20,
            ),
            children: [
              _HistoryHeader(onRefresh: _reload),
              const SizedBox(height: 14),
              _HistoryControls(
                range: _range,
                selectedDate: _selectedDate,
                onRangeChanged: (range) {
                  setState(() {
                    _range = range;
                  });
                },
                onPickDate: _pickDate,
              ),
              const SizedBox(height: 18),
              if (_range == HistoryRange.week)
                const _HistoryPlaceholder()
              else if (snapshot.connectionState != ConnectionState.done)
                SizedBox(
                  height: 220,
                  child: LoadingView(message: _loadState.message),
                )
              else if (snapshot.hasError || !snapshot.hasData)
                _HistoryError(error: snapshot.error, onRetry: _reload)
              else
                _HistoryDayContent(snapshot: snapshot.data!),
            ],
          );
        },
      ),
    );
  }
}

class _HistoryHeader extends StatelessWidget {
  const _HistoryHeader({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Historique',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Consommation passée',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          onPressed: onRefresh,
          tooltip: 'Actualiser',
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }
}

class _HistoryControls extends StatelessWidget {
  const _HistoryControls({
    required this.range,
    required this.selectedDate,
    required this.onRangeChanged,
    required this.onPickDate,
  });

  final HistoryRange range;
  final DateTime selectedDate;
  final ValueChanged<HistoryRange> onRangeChanged;
  final VoidCallback onPickDate;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SegmentedButton<HistoryRange>(
          segments: const [
            ButtonSegment(
              value: HistoryRange.day,
              icon: Icon(Icons.calendar_today),
              label: Text('Jour'),
            ),
            ButtonSegment(
              value: HistoryRange.week,
              icon: Icon(Icons.view_week),
              label: Text('Semaine'),
            ),
          ],
          selected: {range},
          onSelectionChanged: (selection) {
            onRangeChanged(selection.first);
          },
        ),
        OutlinedButton.icon(
          onPressed: onPickDate,
          icon: const Icon(Icons.event),
          label: Text(formatDate(selectedDate)),
        ),
      ],
    );
  }
}

class _HistoryDayContent extends StatelessWidget {
  const _HistoryDayContent({required this.snapshot});

  final LinkySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _HistoryStat(
              icon: Icons.bolt,
              label: 'Total',
              value: '${snapshot.dailyConsumptionKwh.toStringAsFixed(2)} kWh',
              color: snapshot.tempoToday.accent,
            ),
            _HistoryStat(
              icon: Icons.euro,
              label: 'Coût estimé',
              value: '${snapshot.dailyEnergyCostEuro.toStringAsFixed(2)} €',
              color: const Color(0xff0f766e),
            ),
            _HistoryStat(
              icon: Icons.wb_sunny,
              label: 'HP',
              value: '${snapshot.peakConsumptionKwh.toStringAsFixed(2)} kWh',
              color: const Color(0xffd97706),
            ),
            _HistoryStat(
              icon: Icons.nights_stay,
              label: 'HC',
              value: '${snapshot.offPeakConsumptionKwh.toStringAsFixed(2)} kWh',
              color: const Color(0xff2563eb),
            ),
          ],
        ),
        const SizedBox(height: 22),
        SectionHeader(
          title: 'Répartition horaire',
          subtitle: 'Barres colorées selon le tarif Tempo',
          trailing: Text('24 h', style: theme.textTheme.labelLarge),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 280,
          child: _HourlyChart(values: snapshot.hourlyConsumption),
        ),
      ],
    );
  }
}

class _HistoryStat extends StatelessWidget {
  const _HistoryStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: math.min(MediaQuery.sizeOf(context).width - 32, 180),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xffe1e5dc)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      value,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryPlaceholder extends StatelessWidget {
  const _HistoryPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const EmptyHistoryMessage(
      icon: Icons.construction,
      title: 'Vue semaine à venir',
      message:
          "La sélection est prête. Il faudra étendre l'API pour lire plusieurs fichiers journaliers.",
    );
  }
}

class _HistoryError extends StatelessWidget {
  const _HistoryError({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyHistoryMessage(
      icon: Icons.event_busy,
      title: 'Aucune donnée',
      message: error?.toString() ?? 'Impossible de charger cette période.',
      action: FilledButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh),
        label: const Text('Réessayer'),
      ),
    );
  }
}
