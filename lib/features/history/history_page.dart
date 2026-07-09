import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/api_linky_repository.dart';
import '../../models/linky_models.dart';
import '../../shared/shared_widgets.dart';
import '../today/today_page.dart';

enum HistoryRange { day, week, month }

sealed class _HistoryViewData {
  const _HistoryViewData();
}

class _HistoryDayData extends _HistoryViewData {
  const _HistoryDayData(this.snapshot);

  final LinkySnapshot snapshot;
}

class _HistoryWeekData extends _HistoryViewData {
  const _HistoryWeekData({
    required this.startDate,
    required this.endDate,
    required this.entries,
    required this.missingDates,
  });

  final DateTime startDate;
  final DateTime endDate;
  final List<_HistoryWeekEntry> entries;
  final List<DateTime> missingDates;

  int get totalConsumptionWh => entries.fold(
    0,
    (total, entry) => total + entry.snapshot.dailyConsumptionWh,
  );

  double get totalConsumptionKwh => totalConsumptionWh / 1000;

  double get totalCostEuro => entries.fold(
    0,
    (total, entry) => total + entry.snapshot.dailyEnergyCostEuro,
  );

  int get peakConsumptionWh => entries.fold(
    0,
    (total, entry) => total + entry.snapshot.peakConsumptionWh,
  );

  int get offPeakConsumptionWh => entries.fold(
    0,
    (total, entry) => total + entry.snapshot.offPeakConsumptionWh,
  );

  bool get containsToday {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return !today.isBefore(startDate) && !today.isAfter(endDate);
  }
}

class _HistoryWeekEntry {
  const _HistoryWeekEntry({required this.date, required this.snapshot});

  final DateTime date;
  final LinkySnapshot snapshot;
}

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
  late Future<_HistoryViewData> _historyFuture;
  LinkyLoadState _loadState = const LinkyLoadState.connecting();
  var _range = HistoryRange.day;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _repository = widget.repository;
    _historyFuture = _loadSelectedRange();
  }

  void _reload() {
    setState(() {
      _historyFuture = _loadSelectedRange();
    });
  }

  Future<_HistoryViewData> _loadSelectedRange() async {
    _updateLoadState(const LinkyLoadState.connecting());

    switch (_range) {
      case HistoryRange.day:
        _updateLoadState(
          LinkyLoadState.loadingPeriod('du ${formatDate(_selectedDate)}'),
        );
        return _HistoryDayData(
          await _repository.fetchDailySnapshot(_selectedDate),
        );
      case HistoryRange.week:
        return _loadPeriod(
          days: _weekDates(_selectedDate),
          initialPeriodLabel: 'des 7 journées',
          emptyMessage: 'Aucune donnée disponible sur la semaine',
        );
      case HistoryRange.month:
        return _loadPeriod(
          days: _monthDates(_selectedDate),
          initialPeriodLabel: 'du mois',
          emptyMessage: 'Aucune donnée disponible sur le mois',
        );
    }
  }

  Future<_HistoryWeekData> _loadPeriod({
    required List<DateTime> days,
    required String initialPeriodLabel,
    required String emptyMessage,
  }) async {
    _updateLoadState(LinkyLoadState.loadingPeriod(initialPeriodLabel));
    final entries = <_HistoryWeekEntry>[];
    final missingDates = <DateTime>[];

    for (var index = 0; index < days.length; index++) {
      final date = days[index];
      _updateLoadState(
        LinkyLoadState.loadingPeriod(
          'du ${formatDate(date)} (${index + 1}/${days.length})',
        ),
      );
      try {
        final snapshot = await _repository.fetchDailySnapshot(date);
        entries.add(_HistoryWeekEntry(date: date, snapshot: snapshot));
      } catch (_) {
        missingDates.add(date);
      }
    }

    if (entries.isEmpty) {
      throw LinkyApiException(emptyMessage);
    }

    return _HistoryWeekData(
      startDate: days.first,
      endDate: days.last,
      entries: entries,
      missingDates: missingDates,
    );
  }

  List<DateTime> _weekDates(DateTime endDate) {
    final selected = DateTime(endDate.year, endDate.month, endDate.day);
    final monday = selected.subtract(Duration(days: selected.weekday - 1));
    return [
      for (var offset = 0; offset < 7; offset++)
        monday.add(Duration(days: offset)),
    ];
  }

  List<DateTime> _monthDates(DateTime selectedDate) {
    final now = DateTime.now();
    final firstDay = DateTime(selectedDate.year, selectedDate.month);
    final lastDayOfMonth = DateTime(
      selectedDate.year,
      selectedDate.month + 1,
      0,
    );
    final endDay =
        selectedDate.year == now.year && selectedDate.month == now.month
        ? DateTime(now.year, now.month, now.day)
        : lastDayOfMonth;

    return [
      for (
        var date = firstDay;
        !date.isAfter(endDay);
        date = date.add(const Duration(days: 1))
      )
        date,
    ];
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
      _historyFuture = _loadSelectedRange();
    });
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 720;

    return SafeArea(
      child: FutureBuilder<_HistoryViewData>(
        future: _historyFuture,
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
                    _historyFuture = _loadSelectedRange();
                  });
                },
                onPickDate: _pickDate,
              ),
              const SizedBox(height: 18),
              if (snapshot.connectionState != ConnectionState.done)
                SizedBox(
                  height: 220,
                  child: LoadingView(message: _loadState.message),
                )
              else if (snapshot.hasError || !snapshot.hasData)
                _HistoryError(error: snapshot.error, onRetry: _reload)
              else if (snapshot.data! is _HistoryWeekData)
                _HistoryWeekContent(data: snapshot.data! as _HistoryWeekData)
              else
                _HistoryDayContent(
                  snapshot: (snapshot.data! as _HistoryDayData).snapshot,
                ),
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
            ButtonSegment(
              value: HistoryRange.month,
              icon: Icon(Icons.calendar_month),
              label: Text('Mois'),
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
          child: HourlyChart(values: snapshot.hourlyConsumption),
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

class _HistoryWeekContent extends StatelessWidget {
  const _HistoryWeekContent({required this.data});

  final _HistoryWeekData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PeakOffPeakSplitBar(
          peakWh: data.peakConsumptionWh,
          offPeakWh: data.offPeakConsumptionWh,
        ),
        if (data.missingDates.isNotEmpty && !data.containsToday) ...[
          const SizedBox(height: 14),
          InlineStatusMessage(
            icon: Icons.info_outline,
            message:
                '${data.missingDates.length} jour(s) sans données sur cette période.',
          ),
        ],
        const SizedBox(height: 22),
        SectionHeader(
          title: 'Répartition journalière',
          subtitle:
              '${formatDate(data.startDate)} - ${formatDate(data.endDate)}',
          trailing: Text(
            '${data.entries.length} j',
            style: theme.textTheme.labelLarge,
          ),
        ),
        const SizedBox(height: 12),
        _WeekBars(entries: data.entries),
        const SizedBox(height: 16),
        _WeekDayList(data: data),
      ],
    );
  }
}

class _PeakOffPeakSplitBar extends StatelessWidget {
  const _PeakOffPeakSplitBar({required this.peakWh, required this.offPeakWh});

  final int peakWh;
  final int offPeakWh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalWh = peakWh + offPeakWh;
    final peakRatio = totalWh == 0 ? 0.0 : peakWh / totalWh;
    final offPeakRatio = totalWh == 0 ? 0.0 : offPeakWh / totalWh;

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
            Text(
              'Répartition HP / HC',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final peakPercent = (peakRatio * 100).round();
                final offPeakPercent = (offPeakRatio * 100).round();
                return ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: SizedBox(
                    height: 24,
                    child: Stack(
                      children: [
                        const Positioned.fill(
                          child: ColoredBox(color: Color(0xff2563eb)),
                        ),
                        if (totalWh > 0 && offPeakRatio >= 0.18)
                          Align(
                            alignment: Alignment.centerRight,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: Text(
                                'HC $offPeakPercent%',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        if (totalWh == 0)
                          const Positioned.fill(
                            child: ColoredBox(color: Color(0xffe5e7eb)),
                          )
                        else
                          Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              width: constraints.maxWidth * peakRatio,
                              height: double.infinity,
                              child: ColoredBox(
                                color: const Color(0xffd97706),
                                child: peakRatio >= 0.18
                                    ? Center(
                                        child: Text(
                                          'HP $peakPercent%',
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w900,
                                              ),
                                        ),
                                      )
                                    : null,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekBars extends StatelessWidget {
  const _WeekBars({required this.entries});

  final List<_HistoryWeekEntry> entries;

  @override
  Widget build(BuildContext context) {
    final maxWh = entries
        .map((entry) => entry.snapshot.dailyConsumptionWh)
        .fold<int>(0, math.max);
    final dense = entries.length > 10;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xffe1e5dc)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
        child: SizedBox(
          height: 210,
          child: dense
              ? SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final entry in entries) ...[
                        SizedBox(
                          width: 46,
                          child: _WeekBar(
                            entry: entry,
                            maxWh: maxWh,
                            dense: true,
                          ),
                        ),
                        if (entry != entries.last) const SizedBox(width: 6),
                      ],
                    ],
                  ),
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final entry in entries) ...[
                      Expanded(
                        child: _WeekBar(entry: entry, maxWh: maxWh),
                      ),
                      if (entry != entries.last) const SizedBox(width: 8),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

class _WeekBar extends StatelessWidget {
  const _WeekBar({
    required this.entry,
    required this.maxWh,
    this.dense = false,
  });

  final _HistoryWeekEntry entry;
  final int maxWh;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = maxWh == 0 ? 0.0 : entry.snapshot.dailyConsumptionWh / maxWh;
    final barHeight = 126.0 * ratio.clamp(0.0, 1.0);

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '${entry.snapshot.dailyConsumptionKwh.toStringAsFixed(1)} kWh',
            maxLines: 1,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.bottomCenter,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: entry.snapshot.tempoToday.accent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: SizedBox(
              width: double.infinity,
              height: math.max(5, barHeight),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          dense
              ? entry.date.day.toString().padLeft(2, '0')
              : _shortWeekday(entry.date),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _WeekDayList extends StatelessWidget {
  const _WeekDayList({required this.data});

  final _HistoryWeekData data;

  @override
  Widget build(BuildContext context) {
    final entries = data.entries;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xffe1e5dc)),
      ),
      child: Column(
        children: [
          const _WeekTableHeader(),
          const Divider(height: 1),
          for (var index = 0; index < entries.length; index++) ...[
            _WeekDayRow(entry: entries[index]),
            if (index != entries.length - 1) const Divider(height: 1),
          ],
          const Divider(height: 1, thickness: 1.4, color: Color(0xffb8c0b4)),
          _WeekTotalRow(data: data),
        ],
      ),
    );
  }
}

class _WeekTableHeader extends StatelessWidget {
  const _WeekTableHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w800,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      child: Row(
        children: [
          const SizedBox(width: 74),
          const SizedBox(width: 20),
          Expanded(child: Text('Jour', style: style)),
          SizedBox(
            width: 88,
            child: Text('Conso', textAlign: TextAlign.right, style: style),
          ),
          SizedBox(
            width: 74,
            child: Text('Coût', textAlign: TextAlign.right, style: style),
          ),
        ],
      ),
    );
  }
}

class _WeekTotalRow extends StatelessWidget {
  const _WeekTotalRow({required this.data});

  final _HistoryWeekData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Total',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          SizedBox(
            width: 88,
            child: Text(
              '${data.totalConsumptionKwh.toStringAsFixed(2)} kWh',
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          SizedBox(
            width: 74,
            child: Text(
              '${data.totalCostEuro.toStringAsFixed(2)} €',
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekDayRow extends StatelessWidget {
  const _WeekDayRow({required this.entry});

  final _HistoryWeekEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 74,
            child: Text(
              _shortWeekday(entry.date),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: entry.snapshot.tempoToday.accent,
              shape: BoxShape.circle,
            ),
            child: const SizedBox(width: 10, height: 10),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              formatDate(entry.date),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          SizedBox(
            width: 88,
            child: Text(
              '${entry.snapshot.dailyConsumptionKwh.toStringAsFixed(2)} kWh',
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          SizedBox(
            width: 74,
            child: Text(
              '${entry.snapshot.dailyEnergyCostEuro.toStringAsFixed(2)} €',
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _shortWeekday(DateTime date) {
  return switch (date.weekday) {
    DateTime.monday => 'Lun',
    DateTime.tuesday => 'Mar',
    DateTime.wednesday => 'Mer',
    DateTime.thursday => 'Jeu',
    DateTime.friday => 'Ven',
    DateTime.saturday => 'Sam',
    DateTime.sunday => 'Dim',
    _ => '',
  };
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
