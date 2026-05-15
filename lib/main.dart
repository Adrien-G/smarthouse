import 'package:flutter/material.dart';

import 'app/app_settings.dart';
import 'app/smart_house_app.dart';
import 'data/hourly_history_cache.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettings.load();
  final hourlyHistoryCache = await HourlyHistoryCache.load();
  runApp(
    SmartHouseApp(settings: settings, hourlyHistoryCache: hourlyHistoryCache),
  );
}
