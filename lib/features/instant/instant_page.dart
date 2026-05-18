import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/detected_devices.dart';
import '../../models/linky_models.dart';
import '../../shared/shared_widgets.dart';

class InstantConsumptionPage extends StatefulWidget {
  const InstantConsumptionPage({super.key, required this.repository});

  final LinkyRepository repository;

  @override
  State<InstantConsumptionPage> createState() => _InstantConsumptionPageState();
}

class _InstantConsumptionPageState extends State<InstantConsumptionPage> {
  InstantConsumptionSnapshot? _snapshot;
  List<DetectedDevice> _devices = const [];
  Object? _error;
  var _loadingInitial = true;
  var _refreshing = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadDevices();
    _refresh(showInitialLoading: true);
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
  }

  Future<void> _loadDevices() async {
    final devices = await DetectedDeviceStore.load();
    if (!mounted) {
      return;
    }
    setState(() {
      _devices = devices;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
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

    try {
      final snapshot = await widget.repository.fetchInstantConsumption();
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

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 720;
    final snapshot = _snapshot;

    return SafeArea(
      child: ListView(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 16 : 28,
          vertical: 20,
        ),
        children: [
          _InstantHeader(
            onRefresh: () => _refresh(showInitialLoading: snapshot == null),
            isRefreshing: _refreshing,
          ),
          const SizedBox(height: 18),
          if (_loadingInitial && snapshot == null)
            const SizedBox(
              height: 220,
              child: LoadingView(
                message: 'Récupération des 30 dernières minutes...',
              ),
            )
          else if (snapshot == null)
            EmptyHistoryMessage(
              icon: Icons.cloud_off,
              title: 'Données instantanées indisponibles',
              message:
                  _error?.toString() ??
                  'Impossible de charger les dernières mesures.',
              action: FilledButton.icon(
                onPressed: () => _refresh(showInitialLoading: true),
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
            )
          else ...[
            if (_error != null) ...[
              InlineStatusMessage(
                icon: Icons.cloud_off,
                message:
                    'Dernière actualisation impossible, affichage conservé.',
              ),
              const SizedBox(height: 12),
            ],
            _InstantContent(snapshot: snapshot, devices: _devices),
          ],
        ],
      ),
    );
  }
}

class _InstantHeader extends StatelessWidget {
  const _InstantHeader({required this.onRefresh, required this.isRefreshing});

  final VoidCallback onRefresh;
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
                'Instantané',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '30 dernières minutes - actualisation 10 s',
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
      ],
    );
  }
}

class _InstantContent extends StatelessWidget {
  const _InstantContent({required this.snapshot, required this.devices});

  final InstantConsumptionSnapshot snapshot;
  final List<DetectedDevice> devices;

  @override
  Widget build(BuildContext context) {
    final latest = snapshot.latest;

    if (latest == null) {
      return const EmptyHistoryMessage(
        icon: Icons.show_chart,
        title: 'Pas encore de données',
        message: 'Aucune mesure disponible sur les 30 dernières minutes.',
      );
    }

    return Column(
      children: [
        _PhaseTable(
          readings: [
            _PhaseReading(
              label: 'Phase 1',
              currentW: latest.phase1Va,
              labelColor: _InstantPhasesChartPainter.phase1Color,
              trend: _phaseTrend(snapshot.points, (point) => point.phase1Va),
            ),
            _PhaseReading(
              label: 'Phase 2',
              currentW: latest.phase2Va,
              labelColor: _InstantPhasesChartPainter.phase2Color,
              trend: _phaseTrend(snapshot.points, (point) => point.phase2Va),
            ),
            _PhaseReading(
              label: 'Phase 3',
              currentW: latest.phase3Va,
              labelColor: _InstantPhasesChartPainter.phase3Color,
              trend: _phaseTrend(snapshot.points, (point) => point.phase3Va),
            ),
            _PhaseReading(
              label: 'Total',
              currentW: latest.totalVa,
              labelColor: null,
              trend: _phaseTrend(snapshot.points, (point) => point.totalVa),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 280,
          child: _InstantPhasesChart(points: snapshot.points),
        ),
        const SizedBox(height: 12),
        _PossibleDevicesCard(latest: latest, devices: devices),
      ],
    );
  }

  int _averageVa(
    List<PhaseInstantPoint> points,
    int Function(PhaseInstantPoint point) readValue,
  ) {
    if (points.isEmpty) {
      return 0;
    }
    final total = points.fold<int>(0, (sum, point) => sum + readValue(point));
    return (total / points.length).round();
  }

  _PhaseTrend _phaseTrend(
    List<PhaseInstantPoint> points,
    int Function(PhaseInstantPoint point) readValue,
  ) {
    if (points.length < 4) {
      return _PhaseTrend.stable;
    }

    final midpoint = points.length ~/ 2;
    final startAverage = _averageVa(points.take(midpoint).toList(), readValue);
    final endAverage = _averageVa(points.skip(midpoint).toList(), readValue);
    final delta = endAverage - startAverage;
    final threshold = math.max(80, startAverage * 0.08);

    if (delta > threshold) {
      return _PhaseTrend.up;
    }
    if (delta < -threshold) {
      return _PhaseTrend.down;
    }
    return _PhaseTrend.stable;
  }
}

enum _PhaseTrend { up, stable, down }

String _formatInstantWatts(int watts) {
  if (watts >= 1000) {
    return '${(watts / 1000).toStringAsFixed(2)} kW';
  }
  return '$watts W';
}

class _PossibleDevicesCard extends StatelessWidget {
  const _PossibleDevicesCard({required this.latest, required this.devices});

  final PhaseInstantPoint latest;
  final List<DetectedDevice> devices;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final matches = _possibleMatches();

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
                const Icon(Icons.electrical_services, color: Color(0xff1f7a5c)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Appareils possiblement allumes',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (devices.isEmpty)
              Text(
                'Enregistre quelques appareils pour les comparer a la puissance actuelle.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else if (matches.isEmpty)
              Text(
                'Aucun appareil enregistre ne ressort clairement sur la mesure actuelle.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final match in matches.take(3))
                    _PossibleDeviceChip(match: match),
                ],
              ),
          ],
        ),
      ),
    );
  }

  List<_PossibleDeviceMatch> _possibleMatches() {
    final matches = <_PossibleDeviceMatch>[];
    final observed = [latest.phase1Va, latest.phase2Va, latest.phase3Va];

    for (final device in devices) {
      final expected = [
        math.max(0, device.phase1W),
        math.max(0, device.phase2W),
        math.max(0, device.phase3W),
      ];
      final expectedTotal = expected.fold<int>(0, (sum, value) => sum + value);
      if (expectedTotal < 50) {
        continue;
      }

      var deficit = 0;
      for (var index = 0; index < expected.length; index++) {
        deficit += math.max(0, expected[index] - observed[index]);
      }

      final allowedDeficit = math.max(120, expectedTotal * 0.35);
      if (deficit > allowedDeficit) {
        continue;
      }

      final score = (1 - deficit / math.max(1, expectedTotal)) * 100;
      matches.add(
        _PossibleDeviceMatch(
          device: device,
          score: score.clamp(0, 100).round(),
          expectedW: expectedTotal,
        ),
      );
    }

    matches.sort((left, right) => right.score.compareTo(left.score));
    return matches;
  }
}

class _PossibleDeviceChip extends StatelessWidget {
  const _PossibleDeviceChip({required this.match});

  final _PossibleDeviceMatch match;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xfff6f7f3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xffe1e5dc)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_confidenceIcon, size: 18, color: _confidenceColor),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  match.device.name,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '${_formatInstantWatts(match.expectedW)} - ${match.confidenceLabel}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData get _confidenceIcon {
    return match.score >= 85 ? Icons.check_circle : Icons.help_outline;
  }

  Color get _confidenceColor {
    return match.score >= 85
        ? const Color(0xff047857)
        : const Color(0xffb45309);
  }
}

class _PossibleDeviceMatch {
  const _PossibleDeviceMatch({
    required this.device,
    required this.score,
    required this.expectedW,
  });

  final DetectedDevice device;
  final int score;
  final int expectedW;

  String get confidenceLabel {
    if (score >= 85) {
      return 'probable';
    }
    return 'possible';
  }
}

class _InstantPhasesChart extends StatefulWidget {
  const _InstantPhasesChart({required this.points});

  final List<PhaseInstantPoint> points;

  @override
  State<_InstantPhasesChart> createState() => _InstantPhasesChartState();
}

class _InstantPhasesChartState extends State<_InstantPhasesChart> {
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
                  _selectPoint(details.localPosition, constraints.biggest),
              child: CustomPaint(
                painter: _InstantPhasesChartPainter(
                  points: widget.points,
                  selectedIndex: _selectedIndex,
                  labelColor: Theme.of(context).colorScheme.onSurfaceVariant,
                  gridColor: const Color(0xffd7ddd3),
                ),
                child: const SizedBox.expand(),
              ),
            );
          },
        ),
      ),
    );
  }

  void _selectPoint(Offset position, Size size) {
    if (widget.points.length < 2) {
      return;
    }

    const yAxisWidth = _InstantPhasesChartPainter.yAxisWidth;
    const labelHeight = _InstantPhasesChartPainter.labelHeight;
    final chartHeight = size.height - labelHeight;
    final chartWidth = size.width - yAxisWidth;
    if (position.dy < 0 || position.dy > chartHeight) {
      return;
    }

    final ratio = ((position.dx - yAxisWidth) / chartWidth).clamp(0.0, 1.0);
    setState(() {
      _selectedIndex = ((widget.points.length - 1) * ratio).round();
    });
  }
}

class _InstantPhasesChartPainter extends CustomPainter {
  const _InstantPhasesChartPainter({
    required this.points,
    required this.selectedIndex,
    required this.labelColor,
    required this.gridColor,
  });

  final List<PhaseInstantPoint> points;
  final int? selectedIndex;
  final Color labelColor;
  final Color gridColor;

  static const labelHeight = 28.0;
  static const yAxisWidth = 56.0;
  static const phase1Color = Color(0xffd97706);
  static const phase2Color = Color(0xff2563eb);
  static const phase3Color = Color(0xff0f766e);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) {
      return;
    }

    const yAxisLabelWidth = yAxisWidth - 12;
    final chartHeight = size.height - labelHeight;
    final chartWidth = size.width - yAxisWidth;
    final maxValue = points
        .map(
          (point) => math.max(
            point.phase1Va,
            math.max(point.phase2Va, point.phase3Va),
          ),
        )
        .reduce(math.max);
    final scaleMax = math.max(100.0, maxValue.toDouble());
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
        _formatW(value),
        Offset(yAxisLabelWidth / 2, y - 6),
        align: TextAlign.right,
        width: yAxisLabelWidth,
      );
    }

    _drawVerticalGrid(canvas, chartWidth, chartHeight, yAxisWidth, gridPaint);

    _drawLine(
      canvas,
      points.map((p) => p.phase1Va).toList(),
      phase1Color,
      chartWidth,
      chartHeight,
      yAxisWidth,
      scaleMax,
    );
    _drawLine(
      canvas,
      points.map((p) => p.phase2Va).toList(),
      phase2Color,
      chartWidth,
      chartHeight,
      yAxisWidth,
      scaleMax,
    );
    _drawLine(
      canvas,
      points.map((p) => p.phase3Va).toList(),
      phase3Color,
      chartWidth,
      chartHeight,
      yAxisWidth,
      scaleMax,
    );

    _drawSelectedPoint(canvas, chartWidth, chartHeight, yAxisWidth, scaleMax);
    _drawTimeLabels(canvas, chartHeight + 8, chartWidth, yAxisWidth);
  }

  void _drawSelectedPoint(
    Canvas canvas,
    double chartWidth,
    double chartHeight,
    double yAxisWidth,
    double scaleMax,
  ) {
    final index = selectedIndex;
    if (index == null || index < 0 || index >= points.length) {
      return;
    }

    final point = points[index];
    final x = yAxisWidth + chartWidth * index / (points.length - 1);
    final values = [point.phase1Va, point.phase2Va, point.phase3Va];
    final maxPhaseValue = values.reduce(math.max);
    final y = chartHeight - (maxPhaseValue / scaleMax) * (chartHeight - 8);

    final guidePaint = Paint()
      ..color = const Color(0xff111827).withValues(alpha: 0.35)
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(x, 0), Offset(x, chartHeight), guidePaint);

    final markerPaint = Paint()..color = const Color(0xff111827);
    canvas.drawCircle(Offset(x, y), 4.5, markerPaint);

    _drawTooltip(
      canvas,
      anchor: Offset(x, y),
      lines: [
        formatTime(point.timestamp),
        'P1 ${_formatW(point.phase1Va.toDouble())}',
        'P2 ${_formatW(point.phase2Va.toDouble())}',
        'P3 ${_formatW(point.phase3Va.toDouble())}',
      ],
      chartWidth: chartWidth,
      yAxisWidth: yAxisWidth,
      chartHeight: chartHeight,
    );
  }

  void _drawLine(
    Canvas canvas,
    List<int> values,
    Color color,
    double chartWidth,
    double chartHeight,
    double yAxisWidth,
    double scaleMax,
  ) {
    final path = Path();
    for (var index = 0; index < values.length; index++) {
      final x = yAxisWidth + chartWidth * index / (values.length - 1);
      final y = chartHeight - (values[index] / scaleMax) * (chartHeight - 8);
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _drawTimeLabels(
    Canvas canvas,
    double y,
    double chartWidth,
    double yAxisWidth,
  ) {
    for (final marker in _timeMarkers(chartWidth, yAxisWidth)) {
      final x = marker.x.clamp(yAxisWidth + 24, yAxisWidth + chartWidth - 24);
      _drawLabel(canvas, formatTime(marker.timestamp), Offset(x, y), width: 48);
    }
  }

  void _drawVerticalGrid(
    Canvas canvas,
    double chartWidth,
    double chartHeight,
    double yAxisWidth,
    Paint paint,
  ) {
    for (final marker in _timeMarkers(chartWidth, yAxisWidth)) {
      canvas.drawLine(
        Offset(marker.x, 0),
        Offset(marker.x, chartHeight),
        paint,
      );
    }
  }

  List<({DateTime timestamp, double x})> _timeMarkers(
    double chartWidth,
    double yAxisWidth,
  ) {
    final first = points.first.timestamp;
    final last = points.last.timestamp;
    final totalSeconds = last.difference(first).inSeconds;
    if (totalSeconds <= 0) {
      return [(timestamp: first, x: yAxisWidth)];
    }

    final markers = <({DateTime timestamp, double x})>[];
    var cursor = _ceilToFiveMinutes(first);
    while (!cursor.isAfter(last)) {
      final elapsedSeconds = cursor.difference(first).inSeconds;
      final ratio = elapsedSeconds / totalSeconds;
      markers.add((timestamp: cursor, x: yAxisWidth + chartWidth * ratio));
      cursor = cursor.add(const Duration(minutes: 5));
    }

    if (markers.length >= 2) {
      return markers;
    }

    return [
      (timestamp: first, x: yAxisWidth),
      (timestamp: last, x: yAxisWidth + chartWidth),
    ];
  }

  DateTime _ceilToFiveMinutes(DateTime value) {
    final minuteRemainder = value.minute % 5;
    final alreadyAligned =
        minuteRemainder == 0 && value.second == 0 && value.millisecond == 0;
    if (alreadyAligned) {
      return DateTime(
        value.year,
        value.month,
        value.day,
        value.hour,
        value.minute,
      );
    }

    final minutesToAdd = minuteRemainder == 0 ? 5 : 5 - minuteRemainder;
    final rounded = DateTime(
      value.year,
      value.month,
      value.day,
      value.hour,
      value.minute,
    );
    return rounded.add(Duration(minutes: minutesToAdd));
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
    const width = 112.0;
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

  String _formatW(double value) {
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)} kW';
    }
    return '${value.round()} W';
  }

  @override
  bool shouldRepaint(covariant _InstantPhasesChartPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.labelColor != labelColor ||
        oldDelegate.gridColor != gridColor;
  }
}

class _PhaseReading {
  const _PhaseReading({
    required this.label,
    required this.currentW,
    required this.labelColor,
    required this.trend,
  });

  final String label;
  final int currentW;
  final Color? labelColor;
  final _PhaseTrend trend;
}

class _PhaseTable extends StatelessWidget {
  const _PhaseTable({required this.readings});

  final List<_PhaseReading> readings;

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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Text(
                    'Phase',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'Puissance',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  flex: 3,
                  child: Text(
                    'Tendance',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 14),
            for (var index = 0; index < readings.length; index++) ...[
              _PhaseTableRow(reading: readings[index]),
              if (index != readings.length - 1)
                Divider(
                  height: readings[index + 1].label == 'Total' ? 16 : 12,
                  thickness: readings[index + 1].label == 'Total' ? 1.4 : 1,
                  color: readings[index + 1].label == 'Total'
                      ? const Color(0xffb8c0b4)
                      : null,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PhaseTableRow extends StatelessWidget {
  const _PhaseTableRow({required this.reading});

  final _PhaseReading reading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelColor = reading.labelColor ?? theme.colorScheme.onSurfaceVariant;
    final labelWeight = reading.labelColor == null
        ? FontWeight.w700
        : FontWeight.w900;
    final trend = _trendPresentation(reading.trend);

    return Row(
      children: [
        Expanded(
          flex: 4,
          child: Text(
            reading.label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: labelColor,
              fontWeight: labelWeight,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            _formatInstantWatts(reading.currentW),
            textAlign: TextAlign.right,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          flex: 3,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Icon(trend.icon, size: 16, color: trend.color),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  trend.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: trend.color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  ({Color color, IconData icon, String label}) _trendPresentation(
    _PhaseTrend trend,
  ) {
    final trendColor = switch (trend) {
      _PhaseTrend.up => const Color(0xffb91c1c),
      _PhaseTrend.stable => const Color(0xff4b5563),
      _PhaseTrend.down => const Color(0xff047857),
    };
    final trendIcon = switch (trend) {
      _PhaseTrend.up => Icons.trending_up,
      _PhaseTrend.stable => Icons.trending_flat,
      _PhaseTrend.down => Icons.trending_down,
    };
    final trendLabel = switch (trend) {
      _PhaseTrend.up => 'En hausse',
      _PhaseTrend.stable => 'Stable',
      _PhaseTrend.down => 'En baisse',
    };
    return (color: trendColor, icon: trendIcon, label: trendLabel);
  }
}
