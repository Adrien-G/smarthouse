# SmartHouse

Application Flutter locale pour visualiser la consommation electrique Linky via
un Raspberry Pi.

## API Raspberry Pi

Par defaut, l'application appelle :

```text
http://raspberrypi.local:8080
```

Pour utiliser une adresse IP ou un autre hostname :

```bash
flutter run --dart-define=LINKY_API_BASE_URL=http://192.168.1.42:8080
```

Si l'API n'est pas joignable, l'application affiche des donnees de demonstration
pour permettre le developpement hors reseau.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
