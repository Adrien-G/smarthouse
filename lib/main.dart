import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app/app_settings.dart';
import 'data/api_linky_repository.dart';
import 'data/hourly_history_cache.dart';
import 'models/linky_models.dart';
import 'shared/shared_widgets.dart';

part 'app/smart_house_app.dart';
part 'features/today/today_page.dart';
part 'features/instant/instant_page.dart';
part 'features/history/history_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettings.load();
  final hourlyHistoryCache = await HourlyHistoryCache.load();
  runApp(
    SmartHouseApp(settings: settings, hourlyHistoryCache: hourlyHistoryCache),
  );
}
