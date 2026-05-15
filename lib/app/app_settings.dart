import 'package:shared_preferences/shared_preferences.dart';

import '../data/api_linky_repository.dart';

class AppSettings {
  const AppSettings({required this.apiBaseUrl});

  static const apiBaseUrlKey = 'linky_api_base_url';

  final String apiBaseUrl;

  static Future<AppSettings> load() async {
    final preferences = await SharedPreferences.getInstance();
    return AppSettings(
      apiBaseUrl:
          preferences.getString(apiBaseUrlKey) ??
          ApiLinkyRepository.defaultBaseUrl,
    );
  }

  Future<void> save() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(apiBaseUrlKey, apiBaseUrl);
  }
}
