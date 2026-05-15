part of '../../main.dart';

class EnergyDashboardPage extends StatefulWidget {
  const EnergyDashboardPage({
    super.key,
    required this.apiBaseUrl,
    required this.repository,
    required this.onChangeApiBaseUrl,
  });

  final String apiBaseUrl;
  final LinkyRepository repository;
  final ValueChanged<String> onChangeApiBaseUrl;

  @override
  State<EnergyDashboardPage> createState() => _EnergyDashboardPageState();
}

class _EnergyDashboardPageState extends State<EnergyDashboardPage> {
  LinkySnapshot? _snapshot;
  Object? _error;
  LinkyLoadState _loadState = const LinkyLoadState.connecting();
  var _loadingInitial = true;
  var _refreshing = false;

  @override
  void initState() {
    super.initState();
    _loadTodayOnStartup();
  }

  Future<void> _loadTodayOnStartup() async {
    _updateLoadState(const LinkyLoadState.loadingPeriod('du cache local'));
    try {
      final snapshot = await widget.repository.fetchCachedCurrentSnapshot();
      if (!mounted) {
        return;
      }
      setState(() {
        _snapshot = snapshot;
        _error = null;
        _loadingInitial = false;
      });
      await _refresh(showInitialLoading: false);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
      });
      await _refresh(showInitialLoading: true);
    }
  }

  Future<void> _refresh({bool showInitialLoading = false}) async {
    if (!mounted || _refreshing) {
      return;
    }

    if (showInitialLoading || _snapshot == null) {
      setState(() {
        _loadingInitial = true;
        _error = null;
      });
    } else {
      setState(() {
        _refreshing = true;
      });
    }

    _updateLoadState(const LinkyLoadState.connecting());
    try {
      if (widget.repository is ApiLinkyRepository) {
        await (widget.repository as ApiLinkyRepository).checkHealth();
      }

      _updateLoadState(
        const LinkyLoadState.loadingPeriod('des données du jour'),
      );
      final snapshot = await widget.repository.fetchCurrentSnapshot();
      if (!mounted) {
        return;
      }
      setState(() {
        _snapshot = snapshot;
        _error = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingInitial = false;
          _refreshing = false;
        });
      }
    }
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

  Future<void> _changeApiBaseUrl(String value) async {
    widget.onChangeApiBaseUrl(value);
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;

    return Scaffold(
      body: SafeArea(
        child: Builder(
          builder: (context) {
            if (_loadingInitial && snapshot == null) {
              return LoadingView(message: _loadState.message);
            }

            if (snapshot == null) {
              return ErrorView(
                apiBaseUrl: widget.apiBaseUrl,
                error: _error,
                onRetry: () => _refresh(showInitialLoading: true),
                onChangeApiBaseUrl: _changeApiBaseUrl,
              );
            }

            return _DashboardContent(
              snapshot: snapshot,
              apiBaseUrl: widget.apiBaseUrl,
              onRefresh: () => _refresh(showInitialLoading: false),
              onChangeApiBaseUrl: _changeApiBaseUrl,
              isRefreshing: _refreshing,
              refreshError: _error,
            );
          },
        ),
      ),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({
    required this.snapshot,
    required this.apiBaseUrl,
    required this.onRefresh,
    required this.onChangeApiBaseUrl,
    required this.isRefreshing,
    required this.refreshError,
  });

  final LinkySnapshot snapshot;
  final String apiBaseUrl;
  final Future<void> Function() onRefresh;
  final ValueChanged<String> onChangeApiBaseUrl;
  final bool isRefreshing;
  final Object? refreshError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 720;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 16 : 28,
          vertical: 20,
        ),
        children: [
          _Header(
            snapshot: snapshot,
            apiBaseUrl: apiBaseUrl,
            onRefresh: onRefresh,
            onChangeApiBaseUrl: onChangeApiBaseUrl,
            isRefreshing: isRefreshing,
          ),
          const SizedBox(height: 18),
          if (refreshError != null) ...[
            InlineStatusMessage(
              icon: Icons.cloud_off,
              message:
                  'Dernière actualisation impossible, affichage du cache conservé.',
            ),
            const SizedBox(height: 12),
          ],
          _TodaySummaryHero(snapshot: snapshot),
          const SizedBox(height: 14),
          _PeakOffPeakCard(snapshot: snapshot),
          const SizedBox(height: 14),
          _TomorrowTempoCard(snapshot: snapshot),
          const SizedBox(height: 18),
          if (showLegacyMetrics)
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _MetricTile(
                  icon: Icons.bolt,
                  label: 'Puissance instantanée',
                  value: '${snapshot.currentPowerKw.toStringAsFixed(2)} kW',
                  detail: '${snapshot.powerVa} VA',
                  color: const Color(0xffd97706),
                ),
                _MetricTile(
                  icon: Icons.today,
                  label: "Aujourd'hui",
                  value:
                      '${snapshot.dailyConsumptionKwh.toStringAsFixed(2)} kWh',
                  detail: snapshot.tempoToday.label,
                  color: snapshot.tempoToday.accent,
                ),
                _MetricTile(
                  icon: Icons.calendar_month,
                  label: 'Mois en cours',
                  value:
                      '${snapshot.monthlyConsumptionKwh.toStringAsFixed(1)} kWh',
                  detail: 'Index local',
                  color: const Color(0xff4f46e5),
                ),
                _MetricTile(
                  icon: Icons.speed,
                  label: 'Abonnement',
                  value: '${snapshot.subscribedPowerKva} kVA',
                  detail: '${(snapshot.loadRatio * 100).round()} % utilisé',
                  color: const Color(0xff0f766e),
                ),
              ],
            ),
          const SizedBox(height: 22),
          if (showLegacyMetrics)
            SectionHeader(
              title: 'Consommation horaire',
              subtitle: 'Données locales reçues depuis le compteur',
              trailing: Text('24 h', style: theme.textTheme.labelLarge),
            ),
          if (showLegacyMetrics) const SizedBox(height: 12),
          if (snapshot.missingPastHours.isNotEmpty) ...[
            InlineStatusMessage(
              icon: Icons.manage_search,
              message: _missingHoursMessage(snapshot.missingPastHours),
            ),
            const SizedBox(height: 12),
          ],
          SizedBox(
            height: compact ? 220 : 280,
            child: _HourlyChart(values: snapshot.hourlyConsumption),
          ),
        ],
      ),
    );
  }

  String _missingHoursMessage(List<DateTime> hours) {
    final preview = hours.take(4).map((hour) => '${hour.hour}h').join(', ');
    final suffix = hours.length > 4 ? '...' : '';
    final plural = hours.length > 1 ? 's' : '';
    return "${hours.length} heure$plural passée$plural sans donnée dans l'historique : $preview$suffix";
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.snapshot,
    required this.apiBaseUrl,
    required this.onRefresh,
    required this.onChangeApiBaseUrl,
    required this.isRefreshing,
  });

  final LinkySnapshot snapshot;
  final String apiBaseUrl;
  final VoidCallback onRefresh;
  final ValueChanged<String> onChangeApiBaseUrl;
  final bool isRefreshing;

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
                'SmartHouse',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Linky local - mis à jour à ${formatTime(snapshot.timestamp)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isRefreshing) ...[
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
              const SizedBox(width: 10),
            ],
            IconButton.filledTonal(
              onPressed: isRefreshing ? null : onRefresh,
              tooltip: 'Actualiser',
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          onPressed: () => showApiBaseUrlDialog(
            context: context,
            currentValue: apiBaseUrl,
            onSubmitted: onChangeApiBaseUrl,
          ),
          tooltip: 'Configurer',
          icon: const Icon(Icons.settings),
        ),
      ],
    );
  }
}

// ignore: unused_element
class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({required this.snapshot, required this.apiBaseUrl});

  final LinkySnapshot snapshot;
  final String apiBaseUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xffe7f4ee),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xffb7dec8)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: Color(0xff15803d)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Connecté à $apiBaseUrl - dernière mesure à ${formatTime(snapshot.timestamp)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xff14532d),
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

class _TodaySummaryHero extends StatelessWidget {
  const _TodaySummaryHero({required this.snapshot});

  final LinkySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = snapshot.tempoToday.accent;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 560;
            final label = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Aujourd'hui",
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            );
            final consumption = Column(
              crossAxisAlignment: compact
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.end,
              children: [
                Text(
                  '${snapshot.dailyConsumptionKwh.toStringAsFixed(2)} kWh',
                  style: theme.textTheme.displaySmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Coût estimé : ${snapshot.dailyEnergyCostEuro.toStringAsFixed(2)} €',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (showLegacyMetrics)
                  Text(
                    'Coût estimé : ${snapshot.dailyEnergyCostEuro.toStringAsFixed(2)} €',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (showLegacyMetrics) const SizedBox(height: 2),
                if (showLegacyMetrics)
                  Text(
                    'Énergie seule depuis 00:00',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.78),
                    ),
                  ),
              ],
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [label, const SizedBox(height: 18), consumption],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: label),
                const SizedBox(width: 20),
                consumption,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TomorrowTempoCard extends StatelessWidget {
  const _TomorrowTempoCard({required this.snapshot});

  final LinkySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isKnown = snapshot.tempoTomorrow != TempoDayColor.unknown;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xffe1e5dc)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(
              isKnown ? Icons.event_available : Icons.event_note,
              color: isKnown
                  ? snapshot.tempoTomorrow.accent
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Demain',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isKnown
                        ? 'Jour ${snapshot.tempoTomorrow.label}'
                        : 'Couleur à connecter dans un second temps',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ignore: unused_element
class _CompactMetrics extends StatelessWidget {
  const _CompactMetrics({required this.snapshot});

  final LinkySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xffe1e5dc)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 520;
            final children = [
              _CompactMetricItem(
                icon: Icons.bolt,
                label: 'Puissance',
                value: '${snapshot.currentPowerKw.toStringAsFixed(2)} kW',
                detail: '${snapshot.powerVa} VA',
                color: const Color(0xffd97706),
              ),
              _CompactMetricItem(
                icon: Icons.calendar_month,
                label: 'Index compteur',
                value:
                    '${snapshot.monthlyConsumptionKwh.toStringAsFixed(1)} kWh',
                detail: 'Cumul total',
                color: const Color(0xff4f46e5),
              ),
            ];

            if (compact) {
              return Column(
                children: [
                  children.first,
                  const Divider(height: 18),
                  children.last,
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: children.first),
                const SizedBox(height: 42, child: VerticalDivider(width: 18)),
                Expanded(child: children.last),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CompactMetricItem extends StatelessWidget {
  const _CompactMetricItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
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
              const SizedBox(height: 2),
              Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
        Text(
          detail,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _PeakOffPeakCard extends StatelessWidget {
  const _PeakOffPeakCard({required this.snapshot});

  final LinkySnapshot snapshot;

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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showLegacyMetrics)
              Text(
                'HP / HC depuis 00:00',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            if (showLegacyMetrics) const SizedBox(height: 4),
            if (showLegacyMetrics)
              Text(
                'Répartition depuis 00:00, même si la couleur Tempo bascule à 06:00.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            if (showLegacyMetrics) const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 520;
                final children = [
                  _TariffConsumptionPill(
                    icon: Icons.wb_sunny,
                    label: 'Heures pleines',
                    value:
                        '${snapshot.peakConsumptionKwh.toStringAsFixed(2)} kWh',
                    color: const Color(0xffd97706),
                  ),
                  _TariffConsumptionPill(
                    icon: Icons.nights_stay,
                    label: 'Heures creuses',
                    value:
                        '${snapshot.offPeakConsumptionKwh.toStringAsFixed(2)} kWh',
                    color: const Color(0xff2563eb),
                  ),
                ];

                if (compact) {
                  return Column(
                    children: [
                      children.first,
                      const SizedBox(height: 8),
                      children.last,
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: children.first),
                    const SizedBox(width: 8),
                    Expanded(child: children.last),
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

class _TariffConsumptionPill extends StatelessWidget {
  const _TariffConsumptionPill({
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

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: math.min(MediaQuery.sizeOf(context).width - 32, 260),
      child: DecoratedBox(
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
              Icon(icon, color: color),
              const SizedBox(height: 18),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(detail, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

// ignore: unused_element
class _PowerGauge extends StatelessWidget {
  const _PowerGauge({required this.snapshot});

  final LinkySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = snapshot.loadRatio.clamp(0.0, 1.0);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xff18221f),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: 'Charge actuelle',
              subtitle: 'Comparée à la puissance souscrite',
              inverse: true,
              trailing: Icon(
                Icons.electric_meter,
                color: theme.colorScheme.primaryContainer,
              ),
            ),
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                minHeight: 16,
                value: ratio,
                backgroundColor: Colors.white.withValues(alpha: 0.16),
                color: ratio > 0.8
                    ? const Color(0xffef4444)
                    : const Color(0xff7dd3a5),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${snapshot.powerVa} VA sur ${snapshot.subscribedPowerKva * 1000} VA',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.82),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HourlyChart extends StatefulWidget {
  const _HourlyChart({required this.values});

  final List<HourlyConsumption> values;

  @override
  State<_HourlyChart> createState() => _HourlyChartState();
}

class _HourlyChartState extends State<_HourlyChart> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xffe1e5dc)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) =>
                  _selectBar(details.localPosition, constraints.biggest),
              child: CustomPaint(
                painter: _HourlyChartPainter(
                  values: widget.values,
                  selectedIndex: _selectedIndex,
                  barColor: Theme.of(context).colorScheme.primary,
                  gridColor: const Color(0xffd7ddd3),
                  labelColor: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                child: const SizedBox.expand(),
              ),
            );
          },
        ),
      ),
    );
  }

  void _selectBar(Offset position, Size size) {
    if (widget.values.isEmpty) {
      return;
    }

    const labelHeight = _HourlyChartPainter.labelHeight;
    const yAxisWidth = _HourlyChartPainter.yAxisWidth;
    final chartHeight = size.height - labelHeight;
    final chartWidth = size.width - yAxisWidth;
    if (position.dy < 0 || position.dy > chartHeight) {
      return;
    }

    final gap = size.width < 420 ? 3.0 : 6.0;
    final barWidth =
        (chartWidth - gap * (widget.values.length - 1)) / widget.values.length;
    final rawIndex = ((position.dx - yAxisWidth) / (barWidth + gap)).floor();
    final index = rawIndex.clamp(0, widget.values.length - 1);
    setState(() {
      _selectedIndex = index;
    });
  }
}

class _HourlyChartPainter extends CustomPainter {
  const _HourlyChartPainter({
    required this.values,
    required this.selectedIndex,
    required this.barColor,
    required this.gridColor,
    required this.labelColor,
  });

  final List<HourlyConsumption> values;
  final int? selectedIndex;
  final Color barColor;
  final Color gridColor;
  final Color labelColor;

  static const labelHeight = 24.0;
  static const yAxisWidth = 56.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) {
      return;
    }

    const yAxisLabelWidth = yAxisWidth - 12;
    final chartHeight = size.height - labelHeight;
    final chartWidth = size.width - yAxisWidth;
    final maxValue = values.map((e) => e.consumptionWh).reduce(math.max);
    final scaleMax = math.max(100.0, maxValue.toDouble());
    final paint = Paint();
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    const gridLineCount = 5;
    for (var index = 0; index < gridLineCount; index++) {
      final ratio = index / (gridLineCount - 1);
      final y = chartHeight * ratio;
      canvas.drawLine(Offset(yAxisWidth, y), Offset(size.width, y), gridPaint);
      final value = scaleMax * (1 - ratio);
      _drawLabel(
        canvas,
        _formatChartKwh(value),
        Offset(yAxisLabelWidth / 2, y - 6),
        align: TextAlign.right,
        width: yAxisLabelWidth,
      );
    }

    final gap = size.width < 420 ? 3.0 : 6.0;
    final barWidth = (chartWidth - gap * (values.length - 1)) / values.length;

    for (var index = 0; index < values.length; index++) {
      final entry = values[index];
      final normalized = entry.consumptionWh / scaleMax;
      final height = math.max(4.0, normalized * (chartHeight - 8));
      final left = yAxisWidth + index * (barWidth + gap);
      paint.color = _barColor(entry.tempoColor);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, chartHeight - height, barWidth, height),
        const Radius.circular(4),
      );
      canvas.drawRRect(rect, paint);

      if (entry.hour.hour % 3 == 0) {
        _drawLabel(
          canvas,
          '${entry.hour.hour}h',
          Offset(left + barWidth / 2, chartHeight + 8),
        );
      }
    }

    _drawSelectedBar(canvas, chartWidth, chartHeight, yAxisWidth, scaleMax);
  }

  void _drawSelectedBar(
    Canvas canvas,
    double chartWidth,
    double chartHeight,
    double yAxisWidth,
    double scaleMax,
  ) {
    final index = selectedIndex;
    if (index == null || index < 0 || index >= values.length) {
      return;
    }

    final gap = chartWidth + yAxisWidth < 420 ? 3.0 : 6.0;
    final barWidth = (chartWidth - gap * (values.length - 1)) / values.length;
    final entry = values[index];
    final height = math.max(
      4.0,
      (entry.consumptionWh / scaleMax) * (chartHeight - 8),
    );
    final left = yAxisWidth + index * (barWidth + gap);
    final centerX = left + barWidth / 2;
    final top = chartHeight - height;

    final markerPaint = Paint()
      ..color = const Color(0xff111827)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left - 1, top - 1, barWidth + 2, height + 2),
        const Radius.circular(5),
      ),
      markerPaint,
    );

    _drawTooltip(
      canvas,
      anchor: Offset(centerX, top),
      lines: [
        '${entry.hour.hour}h',
        _formatChartKwh(entry.consumptionWh.toDouble()),
        entry.tempoColor.label,
      ],
      chartWidth: chartWidth,
      yAxisWidth: yAxisWidth,
      chartHeight: chartHeight,
    );
  }

  void _drawLabel(
    Canvas canvas,
    String text,
    Offset center, {
    TextAlign align = TextAlign.center,
    double? width,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: labelColor, fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout(maxWidth: width ?? double.infinity);

    painter.paint(canvas, Offset(center.dx - painter.width / 2, center.dy));
  }

  void _drawTooltip(
    Canvas canvas, {
    required Offset anchor,
    required List<String> lines,
    required double chartWidth,
    required double yAxisWidth,
    required double chartHeight,
  }) {
    const width = 104.0;
    final height = 18.0 + lines.length * 16.0;
    var left = anchor.dx - width / 2;
    left = left.clamp(yAxisWidth + 4, yAxisWidth + chartWidth - width - 4);
    var top = anchor.dy - height - 12;
    if (top < 4) {
      top = anchor.dy + 12;
    }
    top = top.clamp(4.0, chartHeight - height - 4);

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, width, height),
      const Radius.circular(8),
    );
    canvas.drawRRect(
      rect,
      Paint()..color = const Color(0xff111827).withValues(alpha: 0.92),
    );

    for (var index = 0; index < lines.length; index++) {
      final painter = TextPainter(
        text: TextSpan(
          text: lines[index],
          style: TextStyle(
            color: Colors.white.withValues(alpha: index == 0 ? 0.94 : 0.82),
            fontSize: index == 0 ? 12 : 11,
            fontWeight: index == 0 ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: width - 16);
      painter.paint(canvas, Offset(left + 8, top + 8 + index * 16));
    }
  }

  String _formatChartKwh(double value) {
    final kwh = value / 1000;
    if (kwh >= 1) {
      return '${kwh.toStringAsFixed(1)} kWh';
    }
    return '${value.round()} Wh';
  }

  Color _barColor(TempoDayColor tempoColor) {
    return switch (tempoColor) {
      TempoDayColor.blue => const Color(0xff3279bd),
      TempoDayColor.white => const Color(0xff9ca3af),
      TempoDayColor.red => const Color(0xffc23b35),
      TempoDayColor.unknown => barColor,
    };
  }

  @override
  bool shouldRepaint(covariant _HourlyChartPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.barColor != barColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.labelColor != labelColor;
  }
}

// ignore: unused_element
class _TempoBand extends StatelessWidget {
  const _TempoBand({required this.snapshot});

  final LinkySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xffe1e5dc)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _TempoChip(label: "Aujourd'hui", color: snapshot.tempoToday),
            _TempoChip(label: 'Demain', color: snapshot.tempoTomorrow),
            const Text("Option Tempo prête à connecter à l'API EDF/RTE"),
          ],
        ),
      ),
    );
  }
}

class _TempoChip extends StatelessWidget {
  const _TempoChip({required this.label, required this.color});

  final String label;
  final TempoDayColor color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: color.accent,
            shape: BoxShape.circle,
          ),
          child: const SizedBox(width: 12, height: 12),
        ),
        const SizedBox(width: 8),
        Text(
          '$label : ${color.label}',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
