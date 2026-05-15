# Raspberry Pi Linky

Ce dossier contient la base du service local qui lit la sortie TIC Linky en mode
standard et ecrit des fichiers journaliers.

## Lancement

```bash
python3 -m pip install pyserial
python3 linky_reader.py
```

Le fichier `config.json` permet de changer le port serie, le dossier de sortie
et le prefixe des fichiers sans modifier le script.

## Format ecrit

Le script conserve ton principe de fichiers journaliers :

```text
/home/adrien/LinkyData/Stat_15-05-2026.txt
```

Chaque ligne est maintenant un CSV separe par `;` avec un en-tete :

```text
timestamp;tariff_code;tariff_label;easf01_wh;...;sinsts3_va;stge
```

Si un fichier du jour existe deja avec l'ancien format prototype, le lecteur le
renomme automatiquement en `.legacy` et recree un fichier propre avec l'en-tete
CSV. Cela evite que l'API lise un melange d'anciens et de nouveaux formats.

Ce format sera plus simple a exposer ensuite a Flutter via une petite API HTTP
locale, tout en restant lisible a la main.

## Suite prevue

Une API locale est disponible avec `api_server.py` :

```bash
python3 api_server.py
```

Depuis un autre appareil du reseau local :

```text
GET /api/health
GET /api/linky/current
GET /api/linky/history?date=2026-05-15
GET /api/linky/history?date=2026-05-15&resolution=hour
GET /api/linky/realtime?duration=30m&resolution=minute
GET /api/tempo
GET /api/config
PUT /api/config
```

Flutter modifierait alors `config.json`, pas le code Python directement. C'est
plus fiable pour Android et Windows, et plus simple a maintenir.

Exemples :

```bash
curl http://raspberrypi.local:8080/api/linky/current
curl http://raspberrypi.local:8080/api/linky/history?date=2026-05-15
curl "http://raspberrypi.local:8080/api/linky/history?date=2026-05-15&resolution=hour"
curl "http://raspberrypi.local:8080/api/linky/realtime?duration=30m&resolution=minute"
curl http://raspberrypi.local:8080/api/tempo
```

Le parametre `resolution` accepte :

```text
raw     toutes les mesures du fichier
minute  un point par minute
hour    un point par heure
```

L'application Flutter utilise `hour` par defaut pour eviter de charger toutes
les mesures fines sur mobile.

## Nom local raspberrypi.local

Si l'API fonctionne avec l'adresse IP mais pas avec `raspberrypi.local`, le
serveur Python n'est pas en cause. Il faut activer la resolution mDNS sur le
Raspberry Pi.

Sur le Raspberry Pi :

```bash
cd /chemin/vers/raspberry
chmod +x setup_mdns.sh
sudo ./setup_mdns.sh raspberrypi
```

Puis tester depuis un autre appareil du reseau local :

```bash
ping raspberrypi.local
curl http://raspberrypi.local:8080/api/health
```

Sur le Raspberry Pi lui-meme, `localhost` doit toujours fonctionner si l'API
est lancee :

```bash
curl http://localhost:8080/api/health
hostname
hostnamectl
systemctl status avahi-daemon
getent hosts raspberrypi.local
```

Si `hostname` affiche par exemple `HAL`, teste aussi :

```bash
curl http://HAL.local:8080/api/health
```

Si le Pi a deja un autre nom, remplace `raspberrypi` par le nom voulu :

```bash
sudo ./setup_mdns.sh smarthouse
curl http://smarthouse.local:8080/api/health
```

Notes :

- Android resout generalement les noms `.local` via mDNS.
- Windows peut parfois necessiter Bonjour ou l'activation de la decouverte
  reseau selon la configuration.
- Le port API doit rester expose sur `0.0.0.0` dans `config.json`, ce qui est
  deja le cas.

## Demarrage automatique

Par defaut, les scripts Python ne redemarrent pas seuls apres un reboot. Pour
les lancer automatiquement, installe les services `systemd` :

```bash
cd /chemin/vers/raspberry
chmod +x install_services.sh
sudo ./install_services.sh /opt/smarthouse adrien adrien
```

Le script installe aussi `python3-serial` et ajoute l'utilisateur au groupe
`dialout` pour l'acces au port serie. Un redemarrage du Raspberry peut etre
necessaire pour que le groupe soit pris en compte partout.

Le script installe deux services :

```text
smarthouse-linky-reader.service
smarthouse-linky-api.service
```

Commandes utiles :

```bash
systemctl status smarthouse-linky-reader.service
systemctl status smarthouse-linky-api.service
journalctl -u smarthouse-linky-reader.service -f
journalctl -u smarthouse-linky-api.service -f
```

Pour redemarrer manuellement :

```bash
sudo systemctl restart smarthouse-linky-reader.service
sudo systemctl restart smarthouse-linky-api.service
```
