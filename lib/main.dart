import 'package:flutter/material.dart';

import 'app/app_settings.dart';
import 'app/smart_house_app.dart';
import 'features/electricity/data/history_day_cache.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettings.load();
  final historyDayCache = await HistoryDayCache.load();
  runApp(SmartHouseApp(settings: settings, historyDayCache: historyDayCache));
}
