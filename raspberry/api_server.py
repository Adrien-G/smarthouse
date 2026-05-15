import csv
import json
from datetime import datetime
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Optional, Union
from urllib.parse import parse_qs, urlparse


BASE_DIR = Path(__file__).resolve().parent
CONFIG_PATH = BASE_DIR / "config.json"
DEFAULT_HOST = "0.0.0.0"
DEFAULT_PORT = 8080


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
                self.send_json({"data": read_history(date)})
            except ValueError as error:
                self.send_json({"error": str(error)}, HTTPStatus.BAD_REQUEST)
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


def read_history(date: Optional[str]) -> list[dict[str, Any]]:
    path = history_path(date)
    if not path.exists():
        return []
    return read_measurements_from_file(path)


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
