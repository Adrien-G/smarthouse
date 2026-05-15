part of '../main.dart';

class SmartHouseApp extends StatelessWidget {
  const SmartHouseApp({
    super.key,
    this.repository,
    this.hourlyHistoryCache,
    this.settings = const AppSettings(
      apiBaseUrl: ApiLinkyRepository.defaultBaseUrl,
    ),
  });

  final LinkyRepository? repository;
  final HourlyHistoryCache? hourlyHistoryCache;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xff1f7a5c);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SmartHouse Linky',
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
        repository: repository,
        hourlyHistoryCache: hourlyHistoryCache,
      ),
    );
  }
}

class SmartHouseHome extends StatefulWidget {
  const SmartHouseHome({
    super.key,
    required this.initialApiBaseUrl,
    this.repository,
    this.hourlyHistoryCache,
  });

  final String initialApiBaseUrl;
  final LinkyRepository? repository;
  final HourlyHistoryCache? hourlyHistoryCache;

  @override
  State<SmartHouseHome> createState() => _SmartHouseHomeState();
}

class _SmartHouseHomeState extends State<SmartHouseHome> {
  var _selectedIndex = 0;
  late String _apiBaseUrl;
  late LinkyRepository _repository;

  @override
  void initState() {
    super.initState();
    _apiBaseUrl = widget.initialApiBaseUrl;
    _repository =
        widget.repository ??
        ApiLinkyRepository(
          baseUrl: _apiBaseUrl,
          hourlyHistoryCache: widget.hourlyHistoryCache,
        );
  }

  Future<void> _changeApiBaseUrl(String value) async {
    final normalized = normalizeApiBaseUrlValue(value);
    await AppSettings(apiBaseUrl: normalized).save();

    setState(() {
      _apiBaseUrl = normalized;
      _repository =
          widget.repository ??
          ApiLinkyRepository(
            baseUrl: normalized,
            hourlyHistoryCache: widget.hourlyHistoryCache,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
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
