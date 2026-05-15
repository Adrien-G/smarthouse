import argparse
import csv
import json
import os
import subprocess
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from sys import exit
from typing import Any, Optional

import serial


CONFIG_PATH = Path(__file__).with_name("config.json")

TARIFF_CODES = {
    "HP BLEU": 0,
    "HC BLEU": 1,
    "HP BLANC": 2,
    "HC BLANC": 3,
    "HP ROUGE": 4,
    "HC ROUGE": 5,
}

CSV_FIELDS = [
    "timestamp",
    "tariff_code",
    "tariff_label",
    "easf01_wh",
    "easf02_wh",
    "easf03_wh",
    "easf04_wh",
    "easf05_wh",
    "easf06_wh",
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


@dataclass(frozen=True)
class SerialSettings:
    port: str
    baudrate: int
    timeout_seconds: int
    parity: str
    bytesize: int
    stopbits: int


@dataclass(frozen=True)
class StorageSettings:
    directory: Path
    file_prefix: str
    date_format: str


@dataclass(frozen=True)
class AppConfig:
    serial: SerialSettings
    storage: StorageSettings


def main() -> None:
    parser = argparse.ArgumentParser(description="Lecteur local Linky TIC standard")
    parser.add_argument(
        "--config",
        default=str(CONFIG_PATH),
        help="Chemin du fichier config.json",
    )
    args = parser.parse_args()

    config = load_config(Path(args.config))
    configure_tty(config.serial.port, config.serial.baudrate)
    reader = LinkyReader(config)
    reader.run()


def load_config(path: Path) -> AppConfig:
    with path.open("r", encoding="utf-8") as file:
        raw = json.load(file)

    serial_config = raw["serial"]
    storage_config = raw["storage"]

    return AppConfig(
        serial=SerialSettings(
            port=serial_config["port"],
            baudrate=int(serial_config["baudrate"]),
            timeout_seconds=int(serial_config["timeout_seconds"]),
            parity=serial_config["parity"],
            bytesize=int(serial_config["bytesize"]),
            stopbits=int(serial_config["stopbits"]),
        ),
        storage=StorageSettings(
            directory=Path(storage_config["directory"]),
            file_prefix=storage_config["file_prefix"],
            date_format=storage_config["date_format"],
        ),
    )


def configure_tty(port: str, baudrate: int) -> None:
    subprocess.run(
        ["stty", "-F", port, str(baudrate), "sane"],
        check=True,
    )


class LinkyReader:
    def __init__(self, config: AppConfig) -> None:
        self.config = config
        self.serial = self._open_serial(config.serial)
        self.current_frame: dict[str, Any] = {}
        self.has_started = False

    def run(self) -> None:
        try:
            while True:
                if self.serial.in_waiting <= 0:
                    continue

                line = self.serial.readline().decode("utf-8", errors="ignore")
                self.handle_line(line)
        except KeyboardInterrupt:
            self.serial.close()
            exit()

    def handle_line(self, line: str) -> None:
        fields = line.strip().split("\t")
        if not fields or not fields[0]:
            return

        key = fields[0]
        value = fields[1] if len(fields) > 1 else ""

        if key == "ADSC":
            if self.has_started and self.current_frame:
                self.write_frame(self.current_frame)
            self.current_frame = {}
            self.has_started = True
            return

        parsed = parse_linky_field(key, value)
        if parsed:
            self.current_frame.update(parsed)

    def write_frame(self, frame: dict[str, Any]) -> None:
        self.config.storage.directory.mkdir(parents=True, exist_ok=True)
        path = self.output_path()
        ensure_csv_header_compatible(path)
        write_header = not path.exists() or path.stat().st_size == 0

        with path.open("a", encoding="utf-8", newline="") as file:
            writer = csv.DictWriter(file, fieldnames=CSV_FIELDS, delimiter=";")
            if write_header:
                writer.writeheader()
            writer.writerow({field: frame.get(field, "") for field in CSV_FIELDS})

    def output_path(self) -> Path:
        file_date = datetime.now().strftime(self.config.storage.date_format)
        filename = f"{self.config.storage.file_prefix}{file_date}.txt"
        return self.config.storage.directory / filename

    @staticmethod
    def _open_serial(settings: SerialSettings) -> serial.Serial:
        parity = serial.PARITY_EVEN if settings.parity == "even" else serial.PARITY_NONE

        return serial.Serial(
            port=settings.port,
            baudrate=settings.baudrate,
            timeout=settings.timeout_seconds,
            parity=parity,
            rtscts=False,
            bytesize=settings.bytesize,
            stopbits=settings.stopbits,
        )


def parse_linky_field(key: str, value: str) -> dict[str, Any]:
    if key == "DATE":
        return {"timestamp": parse_linky_date(value)}

    if key == "LTARF":
        return {
            "tariff_code": get_tariff_code(value),
            "tariff_label": value.strip(),
        }

    if key.startswith("EASF") and key[-2:].isdigit():
        return {f"easf{key[-2:]}_wh": parse_int(value)}

    if key in {"IRMS1", "IRMS2", "IRMS3"}:
        return {f"irms{key[-1]}_a": parse_int(value)}

    if key in {"URMS1", "URMS2", "URMS3"}:
        return {f"urms{key[-1]}_v": parse_int(value)}

    if key in {"SINSTS1", "SINSTS2", "SINSTS3"}:
        return {f"sinsts{key[-1]}_va": parse_int(value)}

    if key == "STGE":
        return {"stge": value.strip()}

    return {}


def ensure_csv_header_compatible(path: Path) -> None:
    if not path.exists() or path.stat().st_size == 0:
        return

    with path.open("r", encoding="utf-8", newline="") as file:
        first_line = file.readline().strip()

    expected_header = ";".join(CSV_FIELDS)
    if first_line == expected_header:
        return

    backup_path = path.with_suffix(f"{path.suffix}.legacy")
    counter = 1
    while backup_path.exists():
        backup_path = path.with_suffix(f"{path.suffix}.legacy{counter}")
        counter += 1

    path.rename(backup_path)


def parse_linky_date(value: str) -> str:
    raw = value.strip()
    if len(raw) >= 13:
        raw = raw[-13:]

    season_marker = raw[0] if raw else ""
    digits = raw[1:] if season_marker in {"E", "H"} else raw

    try:
        parsed = datetime.strptime(digits, "%y%m%d%H%M%S")
        return parsed.isoformat(timespec="seconds")
    except ValueError:
        return raw


def parse_int(value: str) -> int:
    stripped = value.strip().lstrip("0")
    return int(stripped) if stripped else 0


def get_tariff_code(label: str) -> Optional[int]:
    for tariff_label, code in TARIFF_CODES.items():
        if tariff_label in label:
            return code
    return None


if __name__ == "__main__":
    main()
