import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/linky_models.dart';
import '../../shared/shared_widgets.dart';

class DeviceDetectionPage extends StatefulWidget {
  const DeviceDetectionPage({super.key, required this.repository});

  final LinkyRepository repository;

  @override
  State<DeviceDetectionPage> createState() => _DeviceDetectionPageState();
}

class _DeviceDetectionPageState extends State<DeviceDetectionPage> {
  _DevicePowerSample? _baseline;
  _DevicePowerSample? _powered;
  _DeviceDetectionResult? _result;
  Object? _error;
  var _measuringBaseline = false;
  var _measuringPowered = false;

  Future<void> _measureBaseline() async {
    await _measure(
      setLoading: (value) => _measuringBaseline = value,
      onMeasured: (sample) {
        _baseline = sample;
        _powered = null;
        _result = null;
      },
    );
  }

  Future<void> _measurePowered() async {
    await _measure(
      setLoading: (value) => _measuringPowered = value,
      onMeasured: (sample) {
        _powered = sample;
        _result = _DeviceDetectionResult.fromSamples(_baseline!, sample);
      },
    );
  }

  Future<void> _measure({
    required void Function(bool value) setLoading,
    required void Function(_DevicePowerSample sample) onMeasured,
  }) async {
    if (_measuringBaseline || _measuringPowered) {
      return;
    }

    setState(() {
      setLoading(true);
      _error = null;
    });

    try {
      final snapshot = await widget.repository.fetchInstantConsumption();
      final sample = _DevicePowerSample.fromPoints(snapshot.points);
      if (!mounted) {
        return;
      }
      setState(() {
        onMeasured(sample);
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
          setLoading(false);
        });
      }
    }
  }

  void _reset() {
    setState(() {
      _baseline = null;
      _powered = null;
      _result = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 720;

    return SafeArea(
      child: ListView(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 16 : 28,
          vertical: 20,
        ),
        children: [
          const _DeviceDetectionHeader(),
          const SizedBox(height: 18),
          if (_error != null) ...[
            InlineStatusMessage(
              icon: Icons.cloud_off,
              message:
                  'Mesure impossible pour le moment : ${_error.toString()}',
            ),
            const SizedBox(height: 12),
          ],
          _DeviceDetectionSteps(
            baseline: _baseline,
            powered: _powered,
            measuringBaseline: _measuringBaseline,
            measuringPowered: _measuringPowered,
            onMeasureBaseline: _measureBaseline,
            onMeasurePowered: _baseline == null ? null : _measurePowered,
            onReset: _reset,
          ),
          if (_result != null) ...[
            const SizedBox(height: 18),
            _DeviceDetectionResultCard(result: _result!),
          ],
        ],
      ),
    );
  }
}

class _DeviceDetectionHeader extends StatelessWidget {
  const _DeviceDetectionHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Appareils',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Estimation avant / apres allumage',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _DeviceDetectionSteps extends StatelessWidget {
  const _DeviceDetectionSteps({
    required this.baseline,
    required this.powered,
    required this.measuringBaseline,
    required this.measuringPowered,
    required this.onMeasureBaseline,
    required this.onMeasurePowered,
    required this.onReset,
  });

  final _DevicePowerSample? baseline;
  final _DevicePowerSample? powered;
  final bool measuringBaseline;
  final bool measuringPowered;
  final VoidCallback onMeasureBaseline;
  final VoidCallback? onMeasurePowered;
  final VoidCallback onReset;

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
            _MeasureStep(
              index: 1,
              title: 'Reference',
              detail: baseline == null
                  ? 'Laisse l appareil eteint puis lance une mesure.'
                  : 'Mesuree a ${formatTime(baseline!.measuredAt)}',
              value: baseline == null ? null : _formatPower(baseline!.totalW),
              loading: measuringBaseline,
              buttonLabel: baseline == null ? 'Mesurer' : 'Reprendre',
              onPressed: onMeasureBaseline,
            ),
            const Divider(height: 24),
            _MeasureStep(
              index: 2,
              title: 'Appareil allume',
              detail: baseline == null
                  ? 'Mesure d abord la reference.'
                  : 'Allume l appareil, attends quelques secondes, puis mesure.',
              value: powered == null ? null : _formatPower(powered!.totalW),
              loading: measuringPowered,
              buttonLabel: powered == null ? 'Mesurer' : 'Reprendre',
              onPressed: onMeasurePowered,
            ),
            if (baseline != null || powered != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onReset,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Recommencer'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MeasureStep extends StatelessWidget {
  const _MeasureStep({
    required this.index,
    required this.title,
    required this.detail,
    required this.value,
    required this.loading,
    required this.buttonLabel,
    required this.onPressed,
  });

  final int index;
  final String title;
  final String detail;
  final String? value;
  final bool loading;
  final String buttonLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 15,
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(
            '$index',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (value != null) ...[
                const SizedBox(height: 6),
                Text(
                  value!,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 10),
        FilledButton.icon(
          onPressed: loading ? null : onPressed,
          icon: loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.speed),
          label: Text(buttonLabel),
        ),
      ],
    );
  }
}

class _DeviceDetectionResultCard extends StatelessWidget {
  const _DeviceDetectionResultCard({required this.result});

  final _DeviceDetectionResult result;

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
            Text(
              'Resultat estime',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.electrical_services, color: result.color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _formatPower(result.totalDeltaW),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  result.mainPhaseLabel,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _PhaseDelta(label: 'Phase 1', value: result.phase1DeltaW),
                _PhaseDelta(label: 'Phase 2', value: result.phase2DeltaW),
                _PhaseDelta(label: 'Phase 3', value: result.phase3DeltaW),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              result.hint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhaseDelta extends StatelessWidget {
  const _PhaseDelta({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: math.min(MediaQuery.sizeOf(context).width - 32, 150),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xfff6f7f3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xffe1e5dc)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _formatPower(value),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DevicePowerSample {
  const _DevicePowerSample({
    required this.measuredAt,
    required this.phase1W,
    required this.phase2W,
    required this.phase3W,
    required this.sampleCount,
  });

  final DateTime measuredAt;
  final int phase1W;
  final int phase2W;
  final int phase3W;
  final int sampleCount;

  int get totalW => phase1W + phase2W + phase3W;

  static _DevicePowerSample fromPoints(List<PhaseInstantPoint> points) {
    if (points.isEmpty) {
      throw StateError('Aucune mesure instantanee disponible');
    }

    final sorted = [...points]
      ..sort((left, right) {
        return left.timestamp.compareTo(right.timestamp);
      });
    final latest = sorted.last;
    final since = latest.timestamp.subtract(const Duration(seconds: 20));
    var selected = sorted.where((point) {
      return !point.timestamp.isBefore(since);
    }).toList();
    if (selected.length < 3) {
      selected = sorted.skip(math.max(0, sorted.length - 5)).toList();
    }

    int average(int Function(PhaseInstantPoint point) readValue) {
      final total = selected.fold<int>(
        0,
        (sum, point) => sum + readValue(point),
      );
      return (total / selected.length).round();
    }

    return _DevicePowerSample(
      measuredAt: latest.timestamp,
      phase1W: average((point) => point.phase1Va),
      phase2W: average((point) => point.phase2Va),
      phase3W: average((point) => point.phase3Va),
      sampleCount: selected.length,
    );
  }
}

class _DeviceDetectionResult {
  const _DeviceDetectionResult({
    required this.phase1DeltaW,
    required this.phase2DeltaW,
    required this.phase3DeltaW,
  });

  final int phase1DeltaW;
  final int phase2DeltaW;
  final int phase3DeltaW;

  int get totalDeltaW => phase1DeltaW + phase2DeltaW + phase3DeltaW;

  Color get color {
    if (totalDeltaW.abs() < 50) {
      return const Color(0xff6b7280);
    }
    return totalDeltaW >= 0 ? const Color(0xffb45309) : const Color(0xff047857);
  }

  String get mainPhaseLabel {
    final values = [phase1DeltaW.abs(), phase2DeltaW.abs(), phase3DeltaW.abs()];
    final maxValue = values.reduce(math.max);
    if (maxValue < 30) {
      return 'Variation faible';
    }
    return 'Surtout phase ${values.indexOf(maxValue) + 1}';
  }

  String get hint {
    if (totalDeltaW.abs() < 50) {
      return 'Variation faible : la mesure est peut-etre noyee dans le bruit de fond.';
    }
    if (totalDeltaW < 0) {
      return 'La puissance a baisse entre les deux mesures. Un autre appareil a peut-etre change d etat.';
    }
    return 'Estimation basee sur la difference entre les deux mesures. Un appareil variable peut donner un resultat approximatif.';
  }

  static _DeviceDetectionResult fromSamples(
    _DevicePowerSample baseline,
    _DevicePowerSample powered,
  ) {
    return _DeviceDetectionResult(
      phase1DeltaW: powered.phase1W - baseline.phase1W,
      phase2DeltaW: powered.phase2W - baseline.phase2W,
      phase3DeltaW: powered.phase3W - baseline.phase3W,
    );
  }
}

String _formatPower(int watts) {
  final sign = watts < 0 ? '-' : '';
  final absolute = watts.abs();
  if (absolute >= 1000) {
    return '$sign${(absolute / 1000).toStringAsFixed(2)} kW';
  }
  return '$sign$absolute W';
}
