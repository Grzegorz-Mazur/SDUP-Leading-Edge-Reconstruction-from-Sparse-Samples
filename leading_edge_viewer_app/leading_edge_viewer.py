"""
Leading Edge Viewer / Vivado Testbench Comparator
=================================================

Aplikacja okienkowa do porównywania pliku CSV wygenerowanego przez
leading_edge_gui z plikiem *_results.csv wygenerowanym przez testbench Vivado.

Uruchamianie:
    python leading_edge_viewer.py

Budowanie .exe na Windows:
    pip install -r requirements.txt pyinstaller
    pyinstaller --noconsole --onefile --name LeadingEdgeViewer leading_edge_viewer.py
"""

from __future__ import annotations

import csv
import math
import re
import traceback
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Iterable

import numpy as np
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg, NavigationToolbar2Tk
from matplotlib.figure import Figure


METHODS: dict[int, str] = {
    0: "LIN - liniowa",
    1: "EXP - wykładnicza",
    2: "LOG - logarytmiczna/Gauss",
}
METHOD_ALIASES = {
    "linear": 0,
    "lin": 0,
    "liniowa": 0,
    "exponential": 1,
    "exp": 1,
    "wykladnicza": 1,
    "wykładnicza": 1,
    "logarithmic": 2,
    "log": 2,
    "logarytmiczna": 2,
    "gauss": 2,
}

LEGACY_INPUT_COLUMNS = [
    "event_id",
    "t1",
    "A1",
    "t2",
    "A2",
    "t3",
    "A3",
    "true_t0",
    "true_amax",
    "sigma_ns",
    "tau_ns",
    "threshold",
    "charge",
    "true_t_leading",
    "true_t_trailing",
    "true_tot",
]

RESULT_COLUMNS = [
    "event_id",
    "method_id",
    "t1",
    "A1",
    "t2",
    "A2",
    "t3",
    "A3",
    "threshold",
    "true_t0",
    "expected_t0",
    "t0_est",
    "amax_est",
    "error_vs_expected_ns",
    "error_vs_true_ns",
    "start_cycle",
    "valid_cycle",
    "latency_cycles",
    "t0_raw",
    "amax_raw",
    "pass",
]


@dataclass(frozen=True)
class InputEvent:
    event_id: str
    t1: float
    a1: float
    t2: float
    a2: float
    t3: float
    a3: float
    true_t0: float
    true_amax: float
    sigma_ns: float
    tau_ns: float
    threshold: float
    charge: float
    true_t_leading: float
    true_t_trailing: float
    true_tot: float

    @property
    def sample_times(self) -> np.ndarray:
        values = [(self.t1, self.a1), (self.t2, self.a2), (self.t3, self.a3)]
        return np.array([t for t, a in values if math.isfinite(t) and math.isfinite(a) and t > 0.0 and a > 0.0], dtype=float)

    @property
    def sample_amplitudes(self) -> np.ndarray:
        values = [(self.t1, self.a1), (self.t2, self.a2), (self.t3, self.a3)]
        return np.array([a for t, a in values if math.isfinite(t) and math.isfinite(a) and t > 0.0 and a > 0.0], dtype=float)


@dataclass(frozen=True)
class ResultRow:
    event_id: str
    method_id: int
    t1: float
    a1: float
    t2: float
    a2: float
    t3: float
    a3: float
    threshold: float
    true_t0: float
    expected_t0: float
    t0_est: float
    amax_est: float
    error_vs_expected_ns: float
    error_vs_true_ns: float
    start_cycle: int
    valid_cycle: int
    latency_cycles: int
    t0_raw: str
    amax_raw: str
    passed: bool


@dataclass(frozen=True)
class Comparison:
    delta_rtl_expected_ns: float
    abs_delta_rtl_expected_ns: float
    delta_rtl_true_ns: float
    delta_expected_true_ns: float
    delta_amax_true: float
    sample_max_abs_delta: float


def normalize_event_id(value: object) -> str:
    text = str(value).strip()
    if text == "":
        return ""
    try:
        number = float(text)
        if number.is_integer():
            return str(int(number))
    except Exception:
        pass
    return text


def clean_row(row: dict[str, str]) -> dict[str, str]:
    cleaned: dict[str, str] = {}
    for key, value in row.items():
        if key is None:
            continue
        cleaned[key.strip().lstrip("\ufeff")] = value.strip() if isinstance(value, str) else value
    return cleaned


def read_csv_rows(path: Path) -> list[dict[str, str]]:
    with path.open("r", newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        return [clean_row(row) for row in reader]


def get_float(row: dict[str, str], name: str, default: float = float("nan")) -> float:
    value = row.get(name, "")
    if value is None or str(value).strip() == "":
        return default
    try:
        return float(str(value).strip())
    except ValueError:
        return default


def get_int(row: dict[str, str], name: str, default: int = 0) -> int:
    value = row.get(name, "")
    if value is None or str(value).strip() == "":
        return default
    try:
        return int(float(str(value).strip()))
    except ValueError:
        return default


def get_bool(row: dict[str, str], name: str, default: bool = False) -> bool:
    value = str(row.get(name, "")).strip().lower()
    if value in {"1", "true", "yes", "tak", "pass", "passed"}:
        return True
    if value in {"0", "false", "no", "nie", "fail", "failed"}:
        return False
    return default


def parse_input_events(path: Path) -> list[InputEvent]:
    rows = read_csv_rows(path)
    if not rows:
        raise ValueError("Plik wejściowy CSV jest pusty.")

    missing = [column for column in LEGACY_INPUT_COLUMNS if column not in rows[0]]
    if missing:
        raise ValueError(
            "Plik wejściowy nie ma formatu legacy z leading_edge_gui. "
            f"Brakujące kolumny: {', '.join(missing)}"
        )

    events: list[InputEvent] = []
    for row in rows:
        events.append(
            InputEvent(
                event_id=normalize_event_id(row.get("event_id", "")),
                t1=get_float(row, "t1"),
                a1=get_float(row, "A1"),
                t2=get_float(row, "t2"),
                a2=get_float(row, "A2"),
                t3=get_float(row, "t3"),
                a3=get_float(row, "A3"),
                true_t0=get_float(row, "true_t0"),
                true_amax=get_float(row, "true_amax"),
                sigma_ns=get_float(row, "sigma_ns"),
                tau_ns=get_float(row, "tau_ns"),
                threshold=get_float(row, "threshold"),
                charge=get_float(row, "charge"),
                true_t_leading=get_float(row, "true_t_leading"),
                true_t_trailing=get_float(row, "true_t_trailing"),
                true_tot=get_float(row, "true_tot"),
            )
        )
    return events


def parse_result_rows(path: Path) -> list[ResultRow]:
    rows = read_csv_rows(path)
    if not rows:
        raise ValueError("Plik results CSV jest pusty.")

    missing = [column for column in RESULT_COLUMNS if column not in rows[0]]
    if missing:
        raise ValueError(
            "Plik results nie ma oczekiwanego formatu z testbencha Vivado. "
            f"Brakujące kolumny: {', '.join(missing)}"
        )

    results: list[ResultRow] = []
    for row in rows:
        results.append(
            ResultRow(
                event_id=normalize_event_id(row.get("event_id", "")),
                method_id=get_int(row, "method_id"),
                t1=get_float(row, "t1"),
                a1=get_float(row, "A1"),
                t2=get_float(row, "t2"),
                a2=get_float(row, "A2"),
                t3=get_float(row, "t3"),
                a3=get_float(row, "A3"),
                threshold=get_float(row, "threshold"),
                true_t0=get_float(row, "true_t0"),
                expected_t0=get_float(row, "expected_t0"),
                t0_est=get_float(row, "t0_est"),
                amax_est=get_float(row, "amax_est"),
                error_vs_expected_ns=get_float(row, "error_vs_expected_ns"),
                error_vs_true_ns=get_float(row, "error_vs_true_ns"),
                start_cycle=get_int(row, "start_cycle"),
                valid_cycle=get_int(row, "valid_cycle"),
                latency_cycles=get_int(row, "latency_cycles"),
                t0_raw=str(row.get("t0_raw", "")),
                amax_raw=str(row.get("amax_raw", "")),
                passed=get_bool(row, "pass"),
            )
        )
    return results


def detect_method_id_from_path(path: Path) -> int | None:
    """Detect method suffix from names such as fpga_input_seed_1234_0.csv."""
    stem = path.stem
    stem = re.sub(r"_results$", "", stem, flags=re.IGNORECASE)
    match = re.search(r"_(0|1|2)$", stem)
    if match:
        return int(match.group(1))
    return None


def method_id_from_combo(value: str) -> int:
    match = re.match(r"\s*([012])\s*-", value)
    if match:
        return int(match.group(1))
    lowered = value.strip().lower()
    for alias, method_id in METHOD_ALIASES.items():
        if alias in lowered:
            return method_id
    raise ValueError(f"Nieznany tryb interpolacji: {value}")


def method_combo_values() -> list[str]:
    return [f"{method_id} - {name}" for method_id, name in METHODS.items()]


def pmt_pulse(t_ns: np.ndarray, amplitude_pe: float, peak_time_ns: float, sigma_ns: float, tau_ns: float) -> np.ndarray:
    sigma = max(float(sigma_ns), 1e-9)
    tau = max(float(tau_ns), 1e-9)
    x = t_ns - float(peak_time_ns)
    t_match = sigma * sigma / tau
    c_match = math.exp(-0.5 * (t_match / sigma) ** 2)
    gaussian = amplitude_pe * np.exp(-0.5 * (x / sigma) ** 2)
    tail = amplitude_pe * c_match * np.exp(-(x - t_match) / tau)
    return np.where(x <= t_match, gaussian, tail)


def compute_comparison(event: InputEvent, result: ResultRow) -> Comparison:
    sample_pairs = [
        (event.t1, result.t1),
        (event.a1, result.a1),
        (event.t2, result.t2),
        (event.a2, result.a2),
        (event.t3, result.t3),
        (event.a3, result.a3),
        (event.threshold, result.threshold),
    ]
    diffs = [abs(a - b) for a, b in sample_pairs if math.isfinite(a) and math.isfinite(b)]
    sample_delta = max(diffs) if diffs else float("nan")
    delta = result.t0_est - result.expected_t0
    return Comparison(
        delta_rtl_expected_ns=delta,
        abs_delta_rtl_expected_ns=abs(delta),
        delta_rtl_true_ns=result.t0_est - event.true_t0,
        delta_expected_true_ns=result.expected_t0 - event.true_t0,
        delta_amax_true=result.amax_est - event.true_amax,
        sample_max_abs_delta=sample_delta,
    )


def finite_values(values: Iterable[float]) -> list[float]:
    return [float(v) for v in values if math.isfinite(float(v))]


def build_time_grid(event: InputEvent, result: ResultRow) -> np.ndarray:
    xs = finite_values([
        event.t1,
        event.t2,
        event.t3,
        event.true_t_leading,
        event.true_t0,
        result.expected_t0,
        result.t0_est,
    ])
    if not xs:
        return np.linspace(0.0, 40.0, 900)
    x_min = min(xs) - 4.0
    x_max = max(xs) + 6.0
    if math.isfinite(event.true_t_trailing):
        x_max = min(max(x_max, event.true_t0 + 6.0), event.true_t_trailing + 2.0)
    if x_max <= x_min:
        x_max = x_min + 20.0
    return np.linspace(x_min, x_max, 900)


def fit_expected_curve(event: InputEvent, result: ResultRow, t_grid: np.ndarray) -> tuple[np.ndarray, np.ndarray, str]:
    """
    Build a visual reconstruction curve for the selected method.

    The Vivado result CSV stores scalar values, not full curve coefficients. The viewer
    therefore draws the expected curve from the input samples and a second RTL curve as
    the same curve shifted by (t0_est - expected_t0), optionally scaled to amax_est.
    The numeric comparison itself uses the exact CSV columns.
    """
    times = event.sample_times
    amps = event.sample_amplitudes
    if result.method_id == 0:
        if not (math.isfinite(event.t1) and math.isfinite(event.t2) and abs(event.t2 - event.t1) > 1e-12):
            raise ValueError("LIN wymaga poprawnych próbek t1/A1 i t2/A2.")
        slope = (event.a2 - event.a1) / (event.t2 - event.t1)
        expected = slope * (t_grid - result.expected_t0)
        rtl = slope * (t_grid - result.t0_est)
        description = "LIN: linia przez próbki, RTL pokazany jako przesunięcie według t0_est."
        return expected, rtl, description

    if result.method_id == 1:
        if times.size < 3:
            raise ValueError("EXP wymaga 3 dodatnich próbek.")
        if np.any(amps <= 0):
            raise ValueError("EXP wymaga dodatnich amplitud.")
        k, log_c = np.polyfit(times, np.log(amps), 1)
        expected = np.exp(log_c + k * t_grid)
        shifted_t = t_grid - (result.t0_est - result.expected_t0)
        rtl = np.exp(log_c + k * shifted_t)
        local_max = float(np.nanmax(expected)) if np.any(np.isfinite(expected)) else float("nan")
        if math.isfinite(local_max) and local_max > 1e-12 and math.isfinite(result.amax_est):
            rtl *= result.amax_est / local_max
        description = "EXP: dopasowanie log(A)=k*t+c; RTL jako krzywa przesunięta i przeskalowana amax_est."
        return expected, rtl, description

    if result.method_id == 2:
        if times.size < 3:
            raise ValueError("LOG/Gauss wymaga 3 dodatnich próbek.")
        if np.any(amps <= 0):
            raise ValueError("LOG/Gauss wymaga dodatnich amplitud.")
        c2, c1, c0 = np.polyfit(times, np.log(amps), 2)
        expected = np.exp(c0 + c1 * t_grid + c2 * t_grid * t_grid)
        shifted_t = t_grid - (result.t0_est - result.expected_t0)
        rtl = np.exp(c0 + c1 * shifted_t + c2 * shifted_t * shifted_t)
        local_max = float(np.nanmax(expected)) if np.any(np.isfinite(expected)) else float("nan")
        if math.isfinite(local_max) and local_max > 1e-12 and math.isfinite(result.amax_est):
            rtl *= result.amax_est / local_max
        description = "LOG: dopasowanie kwadratowe ln(A); RTL jako krzywa przesunięta i przeskalowana amax_est."
        return expected, rtl, description

    raise ValueError(f"Nieobsługiwany method_id={result.method_id}.")


class LeadingEdgeViewer(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("Leading Edge Viewer - Vivado CSV Comparator")
        self.geometry("1360x860")
        self.minsize(1180, 760)

        self.input_path: Path | None = None
        self.results_path: Path | None = None
        self.input_events: dict[str, InputEvent] = {}
        self.result_rows: list[ResultRow] = []
        self.detected_input_method: int | None = None
        self.current_comparison: Comparison | None = None

        self._build_ui()
        self._log("Aplikacja uruchomiona.")
        self._log("Wczytaj CSV z leading_edge_gui oraz plik *_results.csv z testbencha Vivado.")

    def _build_ui(self) -> None:
        self.columnconfigure(0, weight=0)
        self.columnconfigure(1, weight=1)
        self.rowconfigure(0, weight=1)

        left = ttk.Frame(self, padding=10)
        left.grid(row=0, column=0, sticky="nsw")
        left.columnconfigure(0, weight=1)
        left.rowconfigure(6, weight=1)

        right = ttk.Frame(self, padding=(0, 10, 10, 10))
        right.grid(row=0, column=1, sticky="nsew")
        right.columnconfigure(0, weight=1)
        right.rowconfigure(0, weight=1)
        right.rowconfigure(1, weight=0)

        files = ttk.LabelFrame(left, text="Pliki CSV", padding=10)
        files.grid(row=0, column=0, sticky="ew")
        files.columnconfigure(0, weight=1)

        ttk.Button(files, text="Wczytaj CSV z leading_edge_gui", command=self.on_load_input).grid(row=0, column=0, sticky="ew", pady=3)
        self.input_path_var = tk.StringVar(value="-")
        ttk.Label(files, textvariable=self.input_path_var, wraplength=360).grid(row=1, column=0, sticky="w", pady=(0, 8))

        ttk.Button(files, text="Wczytaj CSV *_results z Vivado", command=self.on_load_results).grid(row=2, column=0, sticky="ew", pady=3)
        self.results_path_var = tk.StringVar(value="-")
        ttk.Label(files, textvariable=self.results_path_var, wraplength=360).grid(row=3, column=0, sticky="w", pady=(0, 4))

        controls = ttk.LabelFrame(left, text="Porównanie", padding=10)
        controls.grid(row=1, column=0, sticky="ew", pady=(10, 0))
        controls.columnconfigure(1, weight=1)

        ttk.Label(controls, text="Event ID:").grid(row=0, column=0, sticky="w", pady=4)
        self.event_var = tk.StringVar(value="-")
        self.event_combo = ttk.Combobox(controls, textvariable=self.event_var, values=[], state="readonly", width=26)
        self.event_combo.grid(row=0, column=1, sticky="ew", pady=4)
        self.event_combo.bind("<<ComboboxSelected>>", lambda _event: self.on_analyze())

        ttk.Label(controls, text="Interpolacja:").grid(row=1, column=0, sticky="w", pady=4)
        self.method_var = tk.StringVar(value=method_combo_values()[0])
        self.method_combo = ttk.Combobox(controls, textvariable=self.method_var, values=method_combo_values(), state="readonly", width=26)
        self.method_combo.grid(row=1, column=1, sticky="ew", pady=4)
        self.method_combo.bind("<<ComboboxSelected>>", lambda _event: self.on_analyze())

        self.detected_method_var = tk.StringVar(value="Wykryty tryb input CSV: -")
        ttk.Label(controls, textvariable=self.detected_method_var).grid(row=2, column=0, columnspan=2, sticky="w", pady=2)

        ttk.Button(controls, text="Analizuj / odśwież wykres", command=self.on_analyze).grid(row=3, column=0, columnspan=2, sticky="ew", pady=(8, 3))
        ttk.Button(controls, text="Zapisz raport porównania CSV", command=self.on_save_report).grid(row=4, column=0, columnspan=2, sticky="ew", pady=3)
        ttk.Button(controls, text="Wyczyść logi", command=self.on_clear_logs).grid(row=5, column=0, columnspan=2, sticky="ew", pady=3)

        summary = ttk.LabelFrame(left, text="Wynik wybranego trybu", padding=10)
        summary.grid(row=2, column=0, sticky="ew", pady=(10, 0))
        summary.columnconfigure(1, weight=1)

        self.summary_vars = {
            "method": tk.StringVar(value="-"),
            "expected": tk.StringVar(value="-"),
            "rtl": tk.StringVar(value="-"),
            "delta": tk.StringVar(value="-"),
            "true": tk.StringVar(value="-"),
            "err_true": tk.StringVar(value="-"),
            "amax": tk.StringVar(value="-"),
            "latency": tk.StringVar(value="-"),
            "pass": tk.StringVar(value="-"),
            "sample_match": tk.StringVar(value="-"),
        }
        rows = [
            ("Tryb:", "method"),
            ("expected_t0 [ns]:", "expected"),
            ("t0_est RTL [ns]:", "rtl"),
            ("RTL - expected [ns]:", "delta"),
            ("true_t0 PMT [ns]:", "true"),
            ("RTL - true [ns]:", "err_true"),
            ("amax_est / true:", "amax"),
            ("Latencja:", "latency"),
            ("PASS:", "pass"),
            ("Zgodność próbek:", "sample_match"),
        ]
        for r, (label, key) in enumerate(rows):
            ttk.Label(summary, text=label).grid(row=r, column=0, sticky="w", pady=2)
            ttk.Label(summary, textvariable=self.summary_vars[key]).grid(row=r, column=1, sticky="w", pady=2)

        table_frame = ttk.LabelFrame(left, text="Wszystkie wyniki testbencha", padding=8)
        table_frame.grid(row=3, column=0, sticky="nsew", pady=(10, 0))
        table_frame.columnconfigure(0, weight=1)
        table_frame.rowconfigure(0, weight=1)
        left.rowconfigure(3, weight=0)

        columns = ("method", "expected", "rtl", "err", "lat", "pass")
        self.results_table = ttk.Treeview(table_frame, columns=columns, show="headings", height=4)
        headings = {
            "method": "method",
            "expected": "expected",
            "rtl": "rtl",
            "err": "err ns",
            "lat": "lat",
            "pass": "pass",
        }
        widths = {"method": 62, "expected": 82, "rtl": 82, "err": 72, "lat": 40, "pass": 46}
        for column in columns:
            self.results_table.heading(column, text=headings[column])
            self.results_table.column(column, width=widths[column], anchor="center", stretch=False)
        self.results_table.grid(row=0, column=0, sticky="ew")
        self.results_table.bind("<<TreeviewSelect>>", self.on_table_select)

        logs_frame = ttk.LabelFrame(left, text="Konsola logów", padding=8)
        logs_frame.grid(row=6, column=0, sticky="nsew", pady=(10, 0))
        logs_frame.columnconfigure(0, weight=1)
        logs_frame.rowconfigure(0, weight=1)

        self.log_text = tk.Text(logs_frame, width=54, height=14, wrap="word", state="disabled")
        self.log_text.grid(row=0, column=0, sticky="nsew")
        scroll = ttk.Scrollbar(logs_frame, command=self.log_text.yview)
        scroll.grid(row=0, column=1, sticky="ns")
        self.log_text.configure(yscrollcommand=scroll.set)

        self.figure = Figure(figsize=(8.8, 5.6), dpi=100)
        self.ax = self.figure.add_subplot(111)
        self.ax.set_title("Porównanie rekonstrukcji leading edge")
        self.ax.set_xlabel("czas [ns]")
        self.ax.set_ylabel("amplituda [p.e.]")
        self.ax.grid(True, alpha=0.35)

        self.canvas = FigureCanvasTkAgg(self.figure, master=right)
        self.canvas.draw()
        self.canvas.get_tk_widget().grid(row=0, column=0, sticky="nsew")
        toolbar = NavigationToolbar2Tk(self.canvas, right, pack_toolbar=False)
        toolbar.update()
        toolbar.grid(row=1, column=0, sticky="ew")

    def _log(self, message: str) -> None:
        timestamp = datetime.now().strftime("%H:%M:%S")
        self.log_text.configure(state="normal")
        self.log_text.insert("end", f"[{timestamp}] {message}\n")
        self.log_text.see("end")
        self.log_text.configure(state="disabled")

    def on_clear_logs(self) -> None:
        self.log_text.configure(state="normal")
        self.log_text.delete("1.0", "end")
        self.log_text.configure(state="disabled")
        self._log("Logi wyczyszczone.")

    def on_load_input(self) -> None:
        path_str = filedialog.askopenfilename(
            title="Wczytaj CSV z leading_edge_gui",
            filetypes=[("CSV", "*.csv"), ("Wszystkie pliki", "*.*")],
        )
        if not path_str:
            return
        try:
            path = Path(path_str)
            events = parse_input_events(path)
            self.input_path = path
            self.input_events = {event.event_id: event for event in events}
            self.detected_input_method = detect_method_id_from_path(path)
            self.input_path_var.set(path.name)
            event_ids = list(self.input_events.keys())
            self.event_combo.configure(values=event_ids)
            if event_ids:
                self.event_var.set(event_ids[0])
            if self.detected_input_method is not None:
                method_label = f"{self.detected_input_method} - {METHODS[self.detected_input_method]}"
                self.method_var.set(method_label)
                self.detected_method_var.set(f"Wykryty tryb input CSV: {method_label}")
                self._log(f"Wczytano input CSV: {path.name}; wykryto method_id={self.detected_input_method}.")
            else:
                self.detected_method_var.set("Wykryty tryb input CSV: brak w nazwie pliku")
                self._log(f"Wczytano input CSV: {path.name}; nie wykryto method_id w nazwie.")
            self._log(f"Liczba eventów w input CSV: {len(events)}.")
            self.on_analyze()
        except Exception as exc:
            self._log(f"BŁĄD wczytywania input CSV: {exc}")
            self._log(traceback.format_exc().splitlines()[-1])
            messagebox.showerror("Błąd wczytywania CSV", str(exc))

    def on_load_results(self) -> None:
        path_str = filedialog.askopenfilename(
            title="Wczytaj CSV *_results z Vivado",
            filetypes=[("CSV", "*.csv"), ("Wszystkie pliki", "*.*")],
        )
        if not path_str:
            return
        try:
            path = Path(path_str)
            rows = parse_result_rows(path)
            self.results_path = path
            self.result_rows = rows
            self.results_path_var.set(path.name)
            methods = sorted({row.method_id for row in rows})
            method_values = [f"{method_id} - {METHODS.get(method_id, 'nieznany')}" for method_id in methods if method_id in METHODS]
            if method_values:
                self.method_combo.configure(values=method_values)
                if self.detected_input_method is not None and self.detected_input_method in methods:
                    self.method_var.set(f"{self.detected_input_method} - {METHODS[self.detected_input_method]}")
                elif method_id_from_combo(self.method_var.get()) not in methods:
                    self.method_var.set(method_values[0])
            self._log(f"Wczytano results CSV: {path.name}; liczba wierszy: {len(rows)}.")
            self._populate_results_table()
            self.on_analyze()
        except Exception as exc:
            self._log(f"BŁĄD wczytywania results CSV: {exc}")
            self._log(traceback.format_exc().splitlines()[-1])
            messagebox.showerror("Błąd wczytywania results", str(exc))

    def selected_event(self) -> InputEvent | None:
        event_id = self.event_var.get()
        return self.input_events.get(event_id)

    def selected_result(self, event_id: str, method_id: int) -> ResultRow | None:
        for row in self.result_rows:
            if row.event_id == event_id and row.method_id == method_id:
                return row
        return None

    def on_table_select(self, _event: object | None = None) -> None:
        selected = self.results_table.selection()
        if not selected:
            return
        item_id = selected[0]
        values = self.results_table.item(item_id, "values")
        if not values:
            return
        method_id = int(str(values[0]).split()[0])
        self.method_var.set(f"{method_id} - {METHODS[method_id]}")
        self.on_analyze()

    def _populate_results_table(self) -> None:
        for item in self.results_table.get_children():
            self.results_table.delete(item)
        if not self.result_rows:
            return
        event_id = self.event_var.get()
        rows = [row for row in self.result_rows if row.event_id == event_id]
        if not rows and self.result_rows:
            rows = self.result_rows
        for row in sorted(rows, key=lambda r: r.method_id):
            self.results_table.insert(
                "",
                "end",
                values=(
                    f"{row.method_id} {METHODS.get(row.method_id, '?')[:3]}",
                    f"{row.expected_t0:.6f}",
                    f"{row.t0_est:.6f}",
                    f"{row.t0_est - row.expected_t0:+.6f}",
                    row.latency_cycles,
                    "1" if row.passed else "0",
                ),
            )

    def on_analyze(self) -> None:
        if not self.input_events or not self.result_rows:
            self._populate_results_table()
            return
        try:
            method_id = method_id_from_combo(self.method_var.get())
            if self.detected_input_method is not None and method_id != self.detected_input_method:
                expected_label = f"{self.detected_input_method} - {METHODS[self.detected_input_method]}"
                selected_label = f"{method_id} - {METHODS[method_id]}"
                msg = (
                    "Wybrana interpolacja nie zgadza się z trybem wykrytym w nazwie input CSV.\n\n"
                    f"Input CSV: {expected_label}\n"
                    f"Wybrano: {selected_label}\n\n"
                    "Wybierz ten sam tryb, aby porównanie było jednoznaczne."
                )
                self._log("UWAGA: niezgodny method_id input CSV i wybranego results CSV.")
                messagebox.showwarning("Niezgodny tryb interpolacji", msg)
                self.method_var.set(expected_label)
                method_id = self.detected_input_method

            event = self.selected_event()
            if event is None:
                raise ValueError("Nie wybrano poprawnego event_id z input CSV.")

            result = self.selected_result(event.event_id, method_id)
            if result is None:
                raise ValueError(f"Brak wiersza results dla event_id={event.event_id}, method_id={method_id}.")

            comparison = compute_comparison(event, result)
            self.current_comparison = comparison
            self._update_summary(event, result, comparison)
            self._populate_results_table()
            self._draw_plot(event, result, comparison)
            self._log(
                f"Porównano event_id={event.event_id}, method_id={method_id}: "
                f"RTL-expected={comparison.delta_rtl_expected_ns:+.6f} ns, "
                f"RTL-true={comparison.delta_rtl_true_ns:+.6f} ns, pass={int(result.passed)}."
            )
        except Exception as exc:
            self._log(f"BŁĄD analizy: {exc}")
            self._log(traceback.format_exc().splitlines()[-1])
            messagebox.showerror("Błąd analizy", str(exc))

    def _update_summary(self, event: InputEvent, result: ResultRow, comparison: Comparison) -> None:
        method_name = METHODS.get(result.method_id, "nieznany")
        self.summary_vars["method"].set(f"{result.method_id} - {method_name}")
        self.summary_vars["expected"].set(f"{result.expected_t0:.9f}")
        self.summary_vars["rtl"].set(f"{result.t0_est:.9f}")
        self.summary_vars["delta"].set(f"{comparison.delta_rtl_expected_ns:+.9f}")
        self.summary_vars["true"].set(f"{event.true_t0:.9f}")
        self.summary_vars["err_true"].set(f"{comparison.delta_rtl_true_ns:+.9f}")
        self.summary_vars["amax"].set(f"{result.amax_est:.9f} / {event.true_amax:.9f} ({comparison.delta_amax_true:+.9f})")
        self.summary_vars["latency"].set(f"{result.latency_cycles} cykli ({result.start_cycle} → {result.valid_cycle})")
        self.summary_vars["pass"].set("TAK" if result.passed else "NIE")
        if math.isfinite(comparison.sample_max_abs_delta):
            self.summary_vars["sample_match"].set(f"max |Δ| = {comparison.sample_max_abs_delta:.3e}")
        else:
            self.summary_vars["sample_match"].set("brak danych")

    def _draw_plot(self, event: InputEvent, result: ResultRow, comparison: Comparison) -> None:
        t_grid = build_time_grid(event, result)
        expected_curve, rtl_curve, curve_desc = fit_expected_curve(event, result, t_grid)
        pmt_curve = pmt_pulse(t_grid, event.true_amax, event.true_t0, event.sigma_ns, event.tau_ns)

        # EXP extrapolation can grow far beyond the PMT peak. For readability the
        # plotted curves are clipped visually, while all numeric comparisons remain
        # based on the raw CSV values.
        y_cap_candidates = finite_values([
            event.true_amax,
            result.amax_est,
            event.threshold,
            float(np.nanmax(event.sample_amplitudes)) if event.sample_amplitudes.size else float("nan"),
        ])
        y_cap = max(y_cap_candidates) * 1.35 if y_cap_candidates else 1.0
        expected_display = np.array(expected_curve, copy=True)
        rtl_display = np.array(rtl_curve, copy=True)
        expected_display[expected_display > y_cap] = np.nan
        rtl_display[rtl_display > y_cap] = np.nan

        self.ax.clear()
        self.ax.plot(t_grid, pmt_curve, label="rzeczywisty impuls PMT z input CSV")
        self.ax.plot(t_grid, expected_display, linestyle="--", label="rekonstrukcja expected/testbench")
        self.ax.plot(t_grid, rtl_display, linestyle="-.", label="rekonstrukcja RTL z results CSV")
        self.ax.scatter(event.sample_times, event.sample_amplitudes, marker="o", label="próbki wejściowe")

        if math.isfinite(event.threshold):
            self.ax.axhline(event.threshold, linestyle=":", label="threshold")
        if math.isfinite(event.true_t_leading):
            self.ax.axvline(event.true_t_leading, linestyle=":", label="true_t_leading")
        if math.isfinite(event.true_t0):
            self.ax.axvline(event.true_t0, linestyle=":", label="true_t0 PMT")
        self.ax.axvline(result.expected_t0, linestyle="--", label="expected_t0")
        self.ax.axvline(result.t0_est, linestyle="-.", label="t0_est RTL")

        title = (
            f"event_id={event.event_id} | {result.method_id} - {METHODS.get(result.method_id, '?')} | "
            f"RTL-expected={comparison.delta_rtl_expected_ns:+.6f} ns"
        )
        self.ax.set_title(title)
        self.ax.set_xlabel("czas [ns]")
        self.ax.set_ylabel("amplituda [p.e.]")
        y_min_candidates = finite_values([0.0, event.threshold, float(np.nanmin(expected_display)), float(np.nanmin(rtl_display))])
        y_min = min(y_min_candidates) if y_min_candidates else 0.0
        self.ax.set_ylim(y_min - 0.08 * y_cap, y_cap)
        self.ax.grid(True, alpha=0.35)
        self.ax.legend(loc="best")
        self.figure.tight_layout()
        self.canvas.draw_idle()
        self._log(curve_desc)

    def on_save_report(self) -> None:
        if not self.input_events or not self.result_rows:
            messagebox.showwarning("Brak danych", "Najpierw wczytaj oba pliki CSV.")
            return
        try:
            event = self.selected_event()
            if event is None:
                raise ValueError("Nie wybrano event_id.")
            method_id = method_id_from_combo(self.method_var.get())
            result = self.selected_result(event.event_id, method_id)
            if result is None:
                raise ValueError("Brak pasującego wyniku testbencha.")
            comparison = compute_comparison(event, result)
            default_name = f"leading_edge_compare_event_{event.event_id}_method_{method_id}.csv"
            path_str = filedialog.asksaveasfilename(
                title="Zapisz raport porównania",
                defaultextension=".csv",
                initialfile=default_name,
                filetypes=[("CSV", "*.csv"), ("Wszystkie pliki", "*.*")],
            )
            if not path_str:
                return
            path = Path(path_str)
            row = {
                "event_id": event.event_id,
                "method_id": method_id,
                "method_name": METHODS.get(method_id, ""),
                "input_csv": self.input_path.name if self.input_path else "",
                "results_csv": self.results_path.name if self.results_path else "",
                "expected_t0": result.expected_t0,
                "t0_est_rtl": result.t0_est,
                "true_t0": event.true_t0,
                "rtl_minus_expected_ns": comparison.delta_rtl_expected_ns,
                "abs_rtl_minus_expected_ns": comparison.abs_delta_rtl_expected_ns,
                "rtl_minus_true_ns": comparison.delta_rtl_true_ns,
                "expected_minus_true_ns": comparison.delta_expected_true_ns,
                "amax_est": result.amax_est,
                "true_amax": event.true_amax,
                "amax_minus_true": comparison.delta_amax_true,
                "latency_cycles": result.latency_cycles,
                "start_cycle": result.start_cycle,
                "valid_cycle": result.valid_cycle,
                "t0_raw": result.t0_raw,
                "amax_raw": result.amax_raw,
                "pass": int(result.passed),
                "sample_max_abs_delta": comparison.sample_max_abs_delta,
            }
            with path.open("w", newline="", encoding="utf-8") as f:
                writer = csv.DictWriter(f, fieldnames=list(row.keys()))
                writer.writeheader()
                writer.writerow(row)
            self._log(f"Zapisano raport porównania: {path.name}")
            messagebox.showinfo("Zapisano", f"Raport zapisany:\n{path}")
        except Exception as exc:
            self._log(f"BŁĄD zapisu raportu: {exc}")
            messagebox.showerror("Błąd zapisu raportu", str(exc))


def main() -> None:
    app = LeadingEdgeViewer()
    app.mainloop()


if __name__ == "__main__":
    main()
