import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/shared_widgets.dart';
import '../data/api_linky_repository.dart';
import '../models/linky_models.dart';

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
    _refresh(showInitialLoading: true);
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
              message: 'Dernière actualisation impossible, affichage conservé.',
            ),
            const SizedBox(height: 12),
          ],
          _TodaySummaryHero(snapshot: snapshot),
          const SizedBox(height: 14),
          _PeakOffPeakCard(snapshot: snapshot),
          const SizedBox(height: 14),
          _TomorrowTempoCard(snapshot: snapshot),
          const SizedBox(height: 18),
          if (snapshot.missingPastHours.isNotEmpty) ...[
            InlineStatusMessage(
              icon: Icons.manage_search,
              message: _missingHoursMessage(snapshot.missingPastHours),
            ),
            const SizedBox(height: 12),
          ],
          SizedBox(
            height: compact ? 220 : 280,
            child: HourlyChart(values: snapshot.hourlyConsumption),
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

class _PeakOffPeakCard extends StatelessWidget {
  const _PeakOffPeakCard({required this.snapshot});

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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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

class HourlyChart extends StatefulWidget {
  const HourlyChart({super.key, required this.values});

  final List<HourlyConsumption> values;

  @override
  State<HourlyChart> createState() => _HourlyChartState();
}

class _HourlyChartState extends State<HourlyChart> {
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
  static const yAxisWidth = 64.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) {
      return;
    }

    const yAxisLabelWidth = yAxisWidth - 12;
    final chartHeight = size.height - labelHeight;
    final chartWidth = size.width - yAxisWidth;
    final maxValue = values.map((e) => e.consumptionWh).reduce(math.max);
    final scaleMax = _niceAxisMax(math.max(100.0, maxValue.toDouble()));
    final axisUsesKwh = scaleMax >= 1000;
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
        _formatChartValue(value, useKwh: axisUsesKwh),
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
      paint.color = _barColor(entry.tempoColor, isPeakHour: entry.isPeakHour);
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
        _formatEnergyValue(entry.consumptionWh.toDouble()),
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

  double _niceAxisMax(double value) {
    if (value <= 250) {
      return 250;
    }
    if (value <= 500) {
      return 500;
    }
    if (value <= 750) {
      return 750;
    }
    if (value <= 1000) {
      return 1000;
    }

    final step = value <= 3000 ? 500.0 : 1000.0;
    return (value / step).ceil() * step;
  }

  String _formatChartValue(double value, {required bool useKwh}) {
    if (useKwh) {
      return '${(value / 1000).toStringAsFixed(1)} kWh';
    }
    return '${value.round()} Wh';
  }

  String _formatEnergyValue(double value) {
    final kwh = value / 1000;
    if (kwh >= 1) {
      return '${kwh.toStringAsFixed(1)} kWh';
    }
    return '${value.round()} Wh';
  }

  Color _barColor(TempoDayColor tempoColor, {required bool isPeakHour}) {
    final baseColor = switch (tempoColor) {
      TempoDayColor.blue => const Color(0xff3279bd),
      TempoDayColor.white => const Color(0xff9ca3af),
      TempoDayColor.red => const Color(0xffc23b35),
      TempoDayColor.unknown => barColor,
    };
    return isPeakHour ? baseColor : Color.lerp(baseColor, Colors.white, 0.22)!;
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
