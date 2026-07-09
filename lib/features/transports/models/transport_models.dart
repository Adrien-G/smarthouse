enum TransportMode { train, bus }

class TransportRouteConfig {
  const TransportRouteConfig({
    required this.id,
    required this.mode,
    required this.title,
    required this.fromLabel,
    required this.toLabel,
    required this.coverage,
    required this.count,
    this.fromUri,
    this.toUri,
    this.fromSearch,
    this.toSearch,
    this.lineCode,
    this.networkName,
  });

  final String id;
  final TransportMode mode;
  final String title;
  final String fromLabel;
  final String toLabel;
  final String coverage;
  final int count;
  final String? fromUri;
  final String? toUri;
  final String? fromSearch;
  final String? toSearch;
  final String? lineCode;
  final String? networkName;
}

class TransportDeparture {
  const TransportDeparture({
    required this.routeId,
    required this.mode,
    required this.lineLabel,
    required this.direction,
    required this.departure,
    this.arrival,
    this.durationMinutes,
    this.platformLabel,
    this.status,
  });

  final String routeId;
  final TransportMode mode;
  final String lineLabel;
  final String direction;
  final DateTime departure;
  final DateTime? arrival;
  final int? durationMinutes;
  final String? platformLabel;
  final String? status;

  bool get hasDisruption => status != null && status!.isNotEmpty;
}

class TransportRouteDepartures {
  const TransportRouteDepartures({
    required this.route,
    required this.departures,
    this.error,
  });

  final TransportRouteConfig route;
  final List<TransportDeparture> departures;
  final Object? error;

  bool get hasError => error != null;
}
