import 'package:shared_preferences/shared_preferences.dart';

import '../features/electricity/data/api_linky_repository.dart';

class AppSettings {
  const AppSettings({required this.apiBaseUrl, this.navitiaApiKey = ''});

  static const apiBaseUrlKey = 'linky_api_base_url';
  static const navitiaApiKeyKey = 'navitia_api_key';

  final String apiBaseUrl;
  final String navitiaApiKey;

  static Future<AppSettings> load() async {
    final preferences = await SharedPreferences.getInstance();
    return AppSettings(
      apiBaseUrl:
          preferences.getString(apiBaseUrlKey) ??
          ApiLinkyRepository.defaultBaseUrl,
      navitiaApiKey: preferences.getString(navitiaApiKeyKey) ?? '',
    );
  }

  Future<void> save() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(apiBaseUrlKey, apiBaseUrl);
    await preferences.setString(navitiaApiKeyKey, navitiaApiKey);
  }
}
