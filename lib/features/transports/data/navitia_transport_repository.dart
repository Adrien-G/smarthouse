import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/transport_models.dart';

class MissingNavitiaApiKeyException implements Exception {
  const MissingNavitiaApiKeyException();
}

class NavitiaTransportRepository {
  NavitiaTransportRepository({
    required this.apiKey,
    http.Client? client,
    this.baseUrl = 'https://api.navitia.io/v1',
  }) : _client = client ?? http.Client();

  final String apiKey;
  final String baseUrl;
  final http.Client _client;
  final Map<String, String> _lineCache = {};
  final Map<String, String> _stopAreaCache = {};

  Future<List<TransportRouteDepartures>> fetchRoutes(
    List<TransportRouteConfig> routes,
  ) async {
    if (apiKey.trim().isEmpty) {
      throw const MissingNavitiaApiKeyException();
    }

    final results = <TransportRouteDepartures>[];
    for (final route in routes) {
      try {
        final departures = await fetchRoute(route);
        results.add(
          TransportRouteDepartures(route: route, departures: departures),
        );
      } catch (error) {
        results.add(
          TransportRouteDepartures(
            route: route,
            departures: const [],
            error: error,
          ),
        );
      }
    }
    return results;
  }

  Future<List<TransportDeparture>> fetchRoute(TransportRouteConfig route) {
    return switch (route.mode) {
      TransportMode.train => _fetchJourneyDepartures(route),
      TransportMode.bus => _fetchBusDepartures(route),
    };
  }

  Future<List<TransportDeparture>> _fetchJourneyDepartures(
    TransportRouteConfig route,
  ) async {
    final fromUri = route.fromUri;
    final toUri = route.toUri;
    if (fromUri == null || toUri == null) {
      return [];
    }

    final response = await _get(
      _uri('/coverage/${route.coverage}/journeys', {
        'from': fromUri,
        'to': toUri,
        'count': route.count.toString(),
        'depth': '1',
        'disable_geojson': 'true',
      }),
    );
    final journeys = _asList(response['journeys']);

    final departures = <TransportDeparture>[];
    for (final journey in journeys) {
      final sections = _asList(journey['sections']);
      for (final section in sections) {
        if (section['type'] != 'public_transport') {
          continue;
        }
        final display = _asMap(section['display_informations']);
        final departureStopPoint = _departureStopPoint(section);
        departures.add(
          TransportDeparture(
            routeId: route.id,
            mode: route.mode,
            lineLabel: _firstText([
              display['headsign'],
              display['code'],
              display['name'],
              route.title,
            ]),
            direction: _cleanDirection(
              _firstText([display['direction'], route.toLabel]),
            ),
            departure: _parseNavitiaDate(
              section['departure_date_time'] as String?,
            ),
            arrival: _tryParseNavitiaDate(
              section['arrival_date_time'] as String?,
            ),
            durationMinutes: _durationMinutes(section['duration']),
            platformLabel: _platformLabel(departureStopPoint),
            status: journey['status'] as String?,
          ),
        );
        break;
      }
    }

    departures.sort((a, b) => a.departure.compareTo(b.departure));
    return departures.take(route.count).toList();
  }

  Future<List<TransportDeparture>> _fetchBusDepartures(
    TransportRouteConfig route,
  ) async {
    final lineId = await _resolveLine(route);
    final fromId = await _resolveStopArea(
      coverage: route.coverage,
      search: route.fromSearch ?? route.fromLabel,
    );
    final toId = await _resolveStopArea(
      coverage: route.coverage,
      search: route.toSearch ?? route.toLabel,
    );

    final response = await _get(
      _uri('/journeys', {
        'from': fromId,
        'to': toId,
        'count': route.count.toString(),
        'depth': '2',
        'disable_geojson': 'true',
        'allowed_id[]': lineId,
        'first_section_mode[]': 'walking',
        'last_section_mode[]': 'walking',
      }),
    );
    final journeys = _asList(response['journeys']);

    final departures = <TransportDeparture>[];
    for (final journey in journeys) {
      final sections = _asList(journey['sections']);
      for (final section in sections) {
        if (section['type'] != 'public_transport') {
          continue;
        }
        final display = _asMap(section['display_informations']);
        final departureStopPoint = _departureStopPoint(section);
        departures.add(
          TransportDeparture(
            routeId: route.id,
            mode: route.mode,
            lineLabel: _firstText([
              display['code'],
              display['headsign'],
              route.title,
            ]),
            direction: _cleanDirection(
              _firstText([display['direction'], route.toLabel]),
            ),
            departure: _parseNavitiaDate(
              section['departure_date_time'] as String?,
            ),
            arrival: _tryParseNavitiaDate(
              section['arrival_date_time'] as String?,
            ),
            durationMinutes: _durationMinutes(section['duration']),
            platformLabel: _platformLabel(departureStopPoint),
            status: journey['status'] as String?,
          ),
        );
        break;
      }
    }

    departures.sort((a, b) => a.departure.compareTo(b.departure));
    return departures.take(route.count).toList();
  }

  Future<String> _resolveLine(TransportRouteConfig route) async {
    final cacheKey =
        '${route.coverage}:${route.networkName}:${route.lineCode}:line';
    final cached = _lineCache[cacheKey];
    if (cached != null) {
      return cached;
    }

    final response = await _get(
      _uri('/coverage/${route.coverage}/pt_objects', {
        'q': route.lineCode ?? route.title,
        'type[]': 'line',
      }),
    );

    for (final object in _asList(response['pt_objects'])) {
      final line = _embeddedObject(object, 'line');
      if (line == null) {
        continue;
      }
      final code = (line['code'] ?? '').toString().toLowerCase();
      final name = (line['name'] ?? '').toString().toLowerCase();
      final network = _asMap(line['network']);
      final networkName = (network['name'] ?? '').toString().toLowerCase();
      final expectedCode = route.lineCode?.toLowerCase();
      final expectedNetwork = route.networkName?.toLowerCase();

      final matchesCode =
          expectedCode == null ||
          code == expectedCode ||
          name.contains(expectedCode);
      final matchesNetwork =
          expectedNetwork == null || networkName.contains(expectedNetwork);
      if (matchesCode && matchesNetwork) {
        final id = line['id'] as String?;
        if (id != null && id.isNotEmpty) {
          _lineCache[cacheKey] = id;
          return id;
        }
      }
    }

    throw StateError('Ligne ${route.lineCode ?? route.title} introuvable');
  }

  Future<String> _resolveStopArea({
    required String coverage,
    required String search,
  }) async {
    final cacheKey = '$coverage:$search:stop_area';
    final cached = _stopAreaCache[cacheKey];
    if (cached != null) {
      return cached;
    }

    final placeResponse = await _get(
      _uri('/coverage/$coverage/places', {'q': search, 'type[]': 'stop_area'}),
    );

    final placeStopAreaId = _firstEmbeddedId(
      placeResponse['places'],
      'stop_area',
    );
    if (placeStopAreaId != null) {
      _stopAreaCache[cacheKey] = placeStopAreaId;
      return placeStopAreaId;
    }

    final ptObjectResponse = await _get(
      _uri('/coverage/$coverage/pt_objects', {
        'q': search,
        'type[]': 'stop_area',
      }),
    );

    final ptObjectStopAreaId = _firstEmbeddedId(
      ptObjectResponse['pt_objects'],
      'stop_area',
    );
    if (ptObjectStopAreaId != null) {
      _stopAreaCache[cacheKey] = ptObjectStopAreaId;
      return ptObjectStopAreaId;
    }

    throw StateError('Arrêt $search introuvable');
  }

  Uri _uri(String path, Map<String, String> queryParameters) {
    return Uri.parse('$baseUrl$path').replace(queryParameters: queryParameters);
  }

  Future<Map<String, dynamic>> _get(Uri uri) async {
    final response = await _client.get(
      uri,
      headers: {
        'Authorization': 'Basic ${base64Encode(utf8.encode('$apiKey:'))}',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Navitia HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw StateError('Réponse Navitia inattendue');
  }

  static Map<String, dynamic> _asMap(Object? value) {
    return value is Map<String, dynamic> ? value : const {};
  }

  static List<Map<String, dynamic>> _asList(Object? value) {
    if (value is! List) {
      return const [];
    }
    return value.whereType<Map<String, dynamic>>().toList();
  }

  static Map<String, dynamic>? _embeddedObject(
    Map<String, dynamic> object,
    String key,
  ) {
    final direct = object[key];
    if (direct is Map<String, dynamic>) {
      return direct;
    }
    final embeddedType = object['embedded_type'];
    if (embeddedType == key) {
      return object[key] is Map<String, dynamic>
          ? object[key] as Map<String, dynamic>
          : null;
    }
    return null;
  }

  static String? _firstEmbeddedId(Object? rawObjects, String key) {
    for (final object in _asList(rawObjects)) {
      final embedded = _embeddedObject(object, key);
      final id = embedded?['id'] as String?;
      if (id != null && id.isNotEmpty) {
        return id;
      }
    }
    return null;
  }

  static Map<String, dynamic> _departureStopPoint(
    Map<String, dynamic> section,
  ) {
    final stopDateTimes = _asList(section['stop_date_times']);
    if (stopDateTimes.isNotEmpty) {
      final stopPoint = _asMap(stopDateTimes.first['stop_point']);
      if (stopPoint.isNotEmpty) {
        return stopPoint;
      }
    }

    return _asMap(section['from']);
  }

  static String? _platformLabel(Map<String, dynamic> stopPoint) {
    final explicitPlatform = _firstText([
      stopPoint['platform_code'],
      stopPoint['platform_name'],
      stopPoint['platform'],
    ]);
    if (explicitPlatform.isNotEmpty) {
      return explicitPlatform;
    }

    final name = _firstText([stopPoint['name'], stopPoint['label']]);
    final match = RegExp(
      r'\b(?:voie|quai|platform)\s*([A-Za-z0-9]+)\b',
      caseSensitive: false,
    ).firstMatch(name);
    if (match != null) {
      return match.group(1);
    }

    return null;
  }

  static String _firstText(List<Object?> values) {
    for (final value in values) {
      final text = value?.toString().trim();
      if (text != null && text.isNotEmpty) {
        return text;
      }
    }
    return '';
  }

  static String _cleanDirection(String direction) {
    final parenthesisIndex = direction.indexOf('(');
    if (parenthesisIndex <= 0) {
      return direction;
    }
    return direction.substring(0, parenthesisIndex).trim();
  }

  static int? _durationMinutes(Object? seconds) {
    if (seconds is int) {
      return (seconds / 60).floor();
    }
    return null;
  }

  static DateTime? _tryParseNavitiaDate(String? value) {
    if (value == null || value.length < 15) {
      return null;
    }
    return _parseNavitiaDate(value);
  }

  static DateTime _parseNavitiaDate(String? value) {
    if (value == null || value.length < 15) {
      throw StateError('Date Navitia invalide');
    }
    return DateTime(
      int.parse(value.substring(0, 4)),
      int.parse(value.substring(4, 6)),
      int.parse(value.substring(6, 8)),
      int.parse(value.substring(9, 11)),
      int.parse(value.substring(11, 13)),
      int.parse(value.substring(13, 15)),
    );
  }
}
