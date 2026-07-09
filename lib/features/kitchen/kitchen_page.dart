import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

class KitchenPage extends StatelessWidget {
  const KitchenPage({super.key, required this.onBackToHub});

  final VoidCallback onBackToHub;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.lightTheme,
      child: HomeScreen(onBackToHub: onBackToHub),
    );
  }
}
