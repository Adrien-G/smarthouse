import csv
import json
from datetime import datetime, timedelta
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Optional, Union
from urllib.error import URLError
from urllib.request import urlopen
from urllib.parse import parse_qs, urlparse


BASE_DIR = Path(__file__).resolve().parent
CONFIG_PATH = BASE_DIR / "config.json"
DEFAULT_HOST = "0.0.0.0"
DEFAULT_PORT = 8080
TEMPO_CACHE_PATH = BASE_DIR / "tempo_cache.json"
TEMPO_TODAY_URL = "https://www.api-couleur-tempo.fr/api/jourTempo/today"
TEMPO_TOMORROW_URL = "https://www.api-couleur-tempo.fr/api/jourTempo/tomorrow"


def main() -> None:
    config = load_config()
    api_config = config.get("api", {})
    host = api_config.get("host", DEFAULT_HOST)
    port = int(api_config.get("port", DEFAULT_PORT))

    server = ThreadingHTTPServer((host, port), LinkyApiHandler)
    print(f"Linky API listening on http://{host}:{port}")
    server.serve_forever()


class LinkyApiHandler(BaseHTTPRequestHandler):
    def do_OPTIONS(self) -> None:
        self.send_json({}, HTTPStatus.NO_CONTENT)

    def do_GET(self) -> None:
        route = urlparse(self.path)

        if route.path == "/api/health":
            self.send_json({"status": "ok"})
            return

        if route.path == "/api/config":
            self.send_json(load_config())
            return

        if route.path == "/api/linky/current":
            self.send_json({"data": read_current_measurement()})
            return

        if route.path == "/api/linky/history":
            try:
                params = parse_qs(route.query)
                date = first_query_value(params, "date")
                resolution = first_query_value(params, "resolution") or "raw"
                self.send_json({"data": read_history(date, resolution)})
            except ValueError as error:
                self.send_json({"error": str(error)}, HTTPStatus.BAD_REQUEST)
            return

        if route.path == "/api/linky/realtime":
            try:
                params = parse_qs(route.query)
                duration = first_query_value(params, "duration") or "30m"
                resolution = first_query_value(params, "resolution") or "raw"
                self.send_json({"data": read_realtime(duration, resolution)})
            except ValueError as error:
                self.send_json({"error": str(error)}, HTTPStatus.BAD_REQUEST)
            return

        if route.path == "/api/tempo":
            self.send_json({"data": read_tempo_colors()})
            return

        self.send_json({"error": "Route introuvable"}, HTTPStatus.NOT_FOUND)

    def do_PUT(self) -> None:
        route = urlparse(self.path)

        if route.path != "/api/config":
            self.send_json({"error": "Route introuvable"}, HTTPStatus.NOT_FOUND)
            return

        try:
            body = self.read_json_body()
            updated = merge_config(load_config(), body)
            save_config(updated)
            self.send_json(updated)
        except ValueError as error:
            self.send_json({"error": str(error)}, HTTPStatus.BAD_REQUEST)

    def read_json_body(self) -> dict[str, Any]:
        raw_length = self.headers.get("Content-Length", "0")
        try:
            length = int(raw_length)
        except ValueError as error:
            raise ValueError("Content-Length invalide") from error

        raw_body = self.rfile.read(length).decode("utf-8")
        if not raw_body:
            return {}

        decoded = json.loads(raw_body)
        if not isinstance(decoded, dict):
            raise ValueError("Le corps JSON doit etre un objet")
        return decoded

    def send_json(
        self,
        payload: Union[dict[str, Any], list[dict[str, Any]]],
        status: HTTPStatus = HTTPStatus.OK,
    ) -> None:
        encoded = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, PUT, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()
        if status != HTTPStatus.NO_CONTENT:
            self.wfile.write(encoded)

    def log_message(self, format: str, *args: Any) -> None:
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        print(f"[{timestamp}] {self.address_string()} {format % args}")


def load_config() -> dict[str, Any]:
    with CONFIG_PATH.open("r", encoding="utf-8") as file:
        return json.load(file)


def save_config(config: dict[str, Any]) -> None:
    with CONFIG_PATH.open("w", encoding="utf-8") as file:
        json.dump(config, file, ensure_ascii=False, indent=2)
        file.write("\n")


def merge_config(current: dict[str, Any], patch: dict[str, Any]) -> dict[str, Any]:
    merged = dict(current)
    for key, value in patch.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = merge_config(merged[key], value)
        else:
            merged[key] = value
    return merged


def read_current_measurement() -> Optional[dict[str, Any]]:
    files = sorted(data_directory().glob(f"{file_prefix()}*.txt"))
    if not files:
        return None

    for path in reversed(files):
        history = read_measurements_from_file(path)
        if history:
            return history[-1]

    return None


def read_history(date: Optional[str], resolution: str = "raw") -> list[dict[str, Any]]:
    path = history_path(date)
    if not path.exists():
        return []

    rows = read_measurements_from_file(path)
    if resolution == "raw":
        return rows
    if resolution == "minute":
        return aggregate_measurements(rows, "minute")
    if resolution == "hour":
        return aggregate_measurements(rows, "hour")

    raise ValueError("Resolution attendue : raw, minute ou hour")


def read_realtime(duration: str = "30m", resolution: str = "raw") -> list[dict[str, Any]]:
    minutes = parse_duration_minutes(duration)
    end = datetime.now()
    start = end - timedelta(minutes=minutes)
    rows = read_history(None, "raw")
    selected = [
        row
        for row in rows
        if is_between(parse_measurement_timestamp(row.get("timestamp")), start, end)
    ]

    if resolution == "raw":
        return selected
    if resolution == "minute":
        return aggregate_measurements(selected, "minute")

    raise ValueError("Resolution attendue pour realtime : raw ou minute")


def parse_duration_minutes(value: str) -> int:
    normalized = value.strip().lower()
    if normalized.endswith("m"):
        minutes = int(normalized[:-1])
    elif normalized.endswith("h"):
        minutes = int(normalized[:-1]) * 60
    else:
        minutes = int(normalized)

    if minutes <= 0 or minutes > 24 * 60:
        raise ValueError("Duration attendue entre 1m et 24h")
    return minutes


def is_between(value: Optional[datetime], start: datetime, end: datetime) -> bool:
    if value is None:
        return False
    return start <= value <= end


def aggregate_measurements(
    rows: list[dict[str, Any]],
    resolution: str,
) -> list[dict[str, Any]]:
    buckets: dict[str, dict[str, Any]] = {}

    for row in rows:
        timestamp = parse_measurement_timestamp(row.get("timestamp"))
        if timestamp is None:
            continue

        bucket_start = truncate_datetime(timestamp, resolution)
        key = bucket_start.isoformat(timespec="seconds")
        aggregate = buckets.get(key)
        if aggregate is None:
            aggregate = {
                "timestamp": key,
                "tariff_label": row.get("tariff_label", ""),
                "sample_count": 0,
            }
            for field in energy_fields():
                aggregate[field] = 0
            for field in instantaneous_fields():
                aggregate[field] = None
            buckets[key] = aggregate

        aggregate["sample_count"] += 1
        aggregate["tariff_label"] = row.get("tariff_label", aggregate["tariff_label"])

        for field in energy_fields():
            aggregate[field] = max_number(aggregate.get(field), row.get(field))

        for field in instantaneous_fields():
            aggregate[field] = row.get(field)

    return [buckets[key] for key in sorted(buckets.keys())]


def truncate_datetime(value: datetime, resolution: str) -> datetime:
    if resolution == "hour":
        return value.replace(minute=0, second=0, microsecond=0)
    if resolution == "minute":
        return value.replace(second=0, microsecond=0)
    raise ValueError("Resolution attendue : raw, minute ou hour")


def parse_measurement_timestamp(value: Any) -> Optional[datetime]:
    if value is None:
        return None
    try:
        return datetime.fromisoformat(str(value))
    except ValueError:
        return None


def max_number(current: Any, candidate: Any) -> Any:
    if current is None:
        return candidate
    if candidate is None:
        return current
    return max(current, candidate)


def energy_fields() -> list[str]:
    return [
        "easf01_wh",
        "easf02_wh",
        "easf03_wh",
        "easf04_wh",
        "easf05_wh",
        "easf06_wh",
    ]


def instantaneous_fields() -> list[str]:
    return [
        "irms1_a",
        "irms2_a",
        "irms3_a",
        "urms1_v",
        "urms2_v",
        "urms3_v",
        "sinsts1_va",
        "sinsts2_va",
        "sinsts3_va",
        "stge",
    ]


def read_tempo_colors() -> dict[str, Any]:
    cached = read_tempo_cache()
    cache_date = cached.get("date") if cached else None
    today = datetime.now().strftime("%Y-%m-%d")
    if cached and cache_date == today:
        return cached

    data = {
        "date": today,
        "today": fetch_tempo_color(TEMPO_TODAY_URL),
        "tomorrow": fetch_tempo_color(TEMPO_TOMORROW_URL),
        "source": "api-couleur-tempo.fr",
        "updated_at": datetime.now().isoformat(timespec="seconds"),
    }
    save_tempo_cache(data)
    return data


def read_tempo_cache() -> Optional[dict[str, Any]]:
    if not TEMPO_CACHE_PATH.exists():
        return None

    try:
        with TEMPO_CACHE_PATH.open("r", encoding="utf-8") as file:
            decoded = json.load(file)
            return decoded if isinstance(decoded, dict) else None
    except (OSError, json.JSONDecodeError):
        return None


def save_tempo_cache(data: dict[str, Any]) -> None:
    with TEMPO_CACHE_PATH.open("w", encoding="utf-8") as file:
        json.dump(data, file, ensure_ascii=False, indent=2)
        file.write("\n")


def fetch_tempo_color(url: str) -> str:
    try:
        with urlopen(url, timeout=5) as response:
            raw = response.read().decode("utf-8").strip()
    except (OSError, URLError):
        return "unknown"

    try:
        decoded = json.loads(raw)
    except json.JSONDecodeError:
        decoded = raw

    return normalize_tempo_color(decoded)


def normalize_tempo_color(value: Any) -> str:
    if isinstance(value, dict):
        for key in ("codeJour", "code", "value", "couleur", "color", "jour"):
            if key in value:
                return normalize_tempo_color(value[key])

    normalized = str(value).strip().lower()
    if normalized in {"1", "bleu", "blue"}:
        return "blue"
    if normalized in {"2", "blanc", "white"}:
        return "white"
    if normalized in {"3", "rouge", "red"}:
        return "red"
    return "unknown"


def read_measurements_from_file(path: Path) -> list[dict[str, Any]]:
    with path.open("r", encoding="utf-8", newline="") as file:
        reader = csv.DictReader(file, delimiter=";")
        if not reader.fieldnames or "timestamp" not in reader.fieldnames:
            return []
        return [normalize_row(row) for row in reader if row]


def normalize_row(row: dict[str, str]) -> dict[str, Any]:
    normalized: dict[str, Any] = {}

    for key, value in row.items():
        if key is None:
            continue
        if value is None:
            normalized[key] = None
        elif key == "timestamp" or key == "tariff_label" or key == "stge":
            normalized[key] = value
        else:
            normalized[key] = parse_number(value)

    return normalized


def parse_number(value: str) -> Optional[Union[int, float]]:
    if value == "":
        return None

    try:
        return int(value)
    except ValueError:
        try:
            return float(value)
        except ValueError:
            return None


def history_path(date: Optional[str]) -> Path:
    selected = parse_requested_date(date) if date else datetime.now()
    filename = f"{file_prefix()}{selected.strftime(date_format())}.txt"
    return data_directory() / filename


def parse_requested_date(value: str) -> datetime:
    for pattern in ("%Y-%m-%d", date_format()):
        try:
            return datetime.strptime(value, pattern)
        except ValueError:
            continue
    raise ValueError("Format de date attendu : YYYY-MM-DD")


def first_query_value(params: dict[str, list[str]], key: str) -> Optional[str]:
    values = params.get(key)
    if not values:
        return None
    return values[0]


def data_directory() -> Path:
    config = load_config()
    return Path(config["storage"]["directory"])


def file_prefix() -> str:
    config = load_config()
    return config["storage"]["file_prefix"]


def date_format() -> str:
    config = load_config()
    return config["storage"]["date_format"]


if __name__ == "__main__":
    main()
