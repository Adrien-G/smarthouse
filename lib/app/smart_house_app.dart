import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../features/electricity/data/api_linky_repository.dart';
import '../features/electricity/data/history_day_cache.dart';
import '../features/electricity/history/history_page.dart';
import '../features/electricity/instant/instant_page.dart';
import '../features/electricity/models/linky_models.dart';
import '../features/electricity/today/today_page.dart';
import '../features/kitchen/kitchen_page.dart';
import '../features/settings/settings_page.dart';
import '../features/transports/transports_page.dart';
import '../shared/shared_widgets.dart';
import 'app_settings.dart';
import 'smart_house_hub_page.dart';

class SmartHouseApp extends StatelessWidget {
  const SmartHouseApp({
    super.key,
    this.repository,
    this.historyDayCache,
    this.settings = const AppSettings(
      apiBaseUrl: ApiLinkyRepository.defaultBaseUrl,
    ),
  });

  final LinkyRepository? repository;
  final HistoryDayCache? historyDayCache;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xff1f7a5c);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SmartHouse',
      locale: const Locale('fr', 'FR'),
      supportedLocales: const [Locale('fr', 'FR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xfff6f7f3),
      ),
      home: SmartHouseHome(
        initialApiBaseUrl: settings.apiBaseUrl,
        initialNavitiaApiKey: settings.navitiaApiKey,
        repository: repository,
        historyDayCache: historyDayCache,
      ),
    );
  }
}

class SmartHouseHome extends StatefulWidget {
  const SmartHouseHome({
    super.key,
    required this.initialApiBaseUrl,
    required this.initialNavitiaApiKey,
    this.repository,
    this.historyDayCache,
  });

  final String initialApiBaseUrl;
  final String initialNavitiaApiKey;
  final LinkyRepository? repository;
  final HistoryDayCache? historyDayCache;

  @override
  State<SmartHouseHome> createState() => _SmartHouseHomeState();
}

class _SmartHouseHomeState extends State<SmartHouseHome> {
  _SmartHouseModule? _activeModule;
  var _selectedIndex = 0;
  late String _apiBaseUrl;
  late String _navitiaApiKey;
  late LinkyRepository _repository;

  @override
  void initState() {
    super.initState();
    _apiBaseUrl = widget.initialApiBaseUrl;
    _navitiaApiKey = widget.initialNavitiaApiKey;
    _repository =
        widget.repository ??
        ApiLinkyRepository(
          baseUrl: _apiBaseUrl,
          historyDayCache: widget.historyDayCache,
        );
  }

  Future<void> _changeApiBaseUrl(String value) async {
    final normalized = normalizeApiBaseUrlValue(value);
    await AppSettings(
      apiBaseUrl: normalized,
      navitiaApiKey: _navitiaApiKey,
    ).save();

    setState(() {
      _apiBaseUrl = normalized;
      _repository =
          widget.repository ??
          ApiLinkyRepository(
            baseUrl: normalized,
            historyDayCache: widget.historyDayCache,
          );
    });
  }

  Future<void> _changeNavitiaApiKey(String value) async {
    await AppSettings(apiBaseUrl: _apiBaseUrl, navitiaApiKey: value).save();

    setState(() {
      _navitiaApiKey = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_activeModule == null) {
      return SmartHouseHubPage(
        onOpenElectricity: () {
          setState(() {
            _activeModule = _SmartHouseModule.electricity;
          });
        },
        onOpenKitchen: () {
          setState(() {
            _activeModule = _SmartHouseModule.kitchen;
          });
        },
        onOpenTransport: () {
          setState(() {
            _activeModule = _SmartHouseModule.transport;
          });
        },
        onOpenSettings: () {
          setState(() {
            _activeModule = _SmartHouseModule.settings;
          });
        },
      );
    }

    if (_activeModule == _SmartHouseModule.kitchen) {
      return KitchenPage(
        onBackToHub: () {
          setState(() {
            _activeModule = null;
          });
        },
      );
    }

    if (_activeModule == _SmartHouseModule.transport) {
      return TransportsPage(
        navitiaApiKey: _navitiaApiKey,
        onBackToHub: () {
          setState(() {
            _activeModule = null;
          });
        },
        onOpenSettings: () {
          setState(() {
            _activeModule = _SmartHouseModule.settings;
          });
        },
      );
    }

    if (_activeModule == _SmartHouseModule.settings) {
      return SettingsPage(
        navitiaApiKey: _navitiaApiKey,
        onChangeNavitiaApiKey: _changeNavitiaApiKey,
        onBackToHub: () {
          setState(() {
            _activeModule = null;
          });
        },
      );
    }

    final page = switch (_selectedIndex) {
      0 => EnergyDashboardPage(
        key: ValueKey('today-page-$_apiBaseUrl'),
        apiBaseUrl: _apiBaseUrl,
        repository: _repository,
        onChangeApiBaseUrl: _changeApiBaseUrl,
      ),
      1 => InstantConsumptionPage(
        key: ValueKey('instant-page-$_apiBaseUrl'),
        repository: _repository,
      ),
      _ => HistoryPage(
        key: ValueKey('history-page-$_apiBaseUrl'),
        apiBaseUrl: _apiBaseUrl,
        repository: _repository,
      ),
    };

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () {
            setState(() {
              _activeModule = null;
            });
          },
          tooltip: 'Accueil',
          icon: const Icon(Icons.home_outlined),
        ),
        title: const Text('Électricité'),
      ),
      body: page,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: "Aujourd'hui",
          ),
          NavigationDestination(
            icon: Icon(Icons.show_chart),
            selectedIcon: Icon(Icons.show_chart),
            label: 'Instantané',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'Historique',
          ),
        ],
      ),
    );
  }
}

enum _SmartHouseModule { electricity, kitchen, transport, settings }
