import '../models/transport_models.dart';

class TransportConfig {
  const TransportConfig._();

  static const routes = [
    TransportRouteConfig(
      id: 'ter-vendenheim-strasbourg',
      mode: TransportMode.train,
      title: 'TER',
      fromLabel: 'Vendenheim',
      toLabel: 'Strasbourg',
      coverage: 'sncf',
      fromUri: 'stop_area:SNCF:87212118',
      toUri: 'stop_area:SNCF:87212027',
      count: 6,
    ),
    TransportRouteConfig(
      id: 'ter-strasbourg-vendenheim',
      mode: TransportMode.train,
      title: 'TER',
      fromLabel: 'Strasbourg',
      toLabel: 'Vendenheim',
      coverage: 'sncf',
      fromUri: 'stop_area:SNCF:87212027',
      toUri: 'stop_area:SNCF:87212118',
      count: 6,
    ),
    TransportRouteConfig(
      id: 'bus-h-gare-parlement',
      mode: TransportMode.bus,
      title: 'Bus H',
      fromLabel: 'Gare Centrale',
      toLabel: 'Parlement européen',
      coverage: 'fr-grand-est',
      fromSearch: 'Gare Centrale Strasbourg',
      toSearch: 'Parlement européen Strasbourg',
      lineCode: 'H',
      networkName: 'CTS',
      count: 6,
    ),
    TransportRouteConfig(
      id: 'bus-h-parlement-gare',
      mode: TransportMode.bus,
      title: 'Bus H',
      fromLabel: 'Parlement européen',
      toLabel: 'Gare Centrale',
      coverage: 'fr-grand-est',
      fromSearch: 'Parlement européen Strasbourg',
      toSearch: 'Gare Centrale Strasbourg',
      lineCode: 'H',
      networkName: 'CTS',
      count: 6,
    ),
  ];
}
