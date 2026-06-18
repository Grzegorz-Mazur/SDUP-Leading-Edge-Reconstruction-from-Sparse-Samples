"""
Leading Edge PMT Test Generator / Reconstruction GUI
====================================================

Prosta aplikacja okienkowa do szybkiego generowania impulsu PMT,
rekonstrukcji zbocza z rzadkich próbek i eksportu wektorów CSV dla FPGA.

Uruchamianie:
    python leading_edge_gui.py

Budowanie .exe na Windows:
    pip install -r requirements.txt pyinstaller
    pyinstaller --noconsole --onefile --name LeadingEdgeTester leading_edge_gui.py
"""

from __future__ import annotations

import csv
import math
import traceback
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Callable

import numpy as np
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg, NavigationToolbar2Tk
from matplotlib.figure import Figure


MODE_CODES = {
    "LIN - liniowa": 0,
    "EXP - wykładnicza": 1,
    "LOG - logarytmiczna/Gauss": 2,
}

STATUS_OK = 0
STATUS_INPUT_ERROR = 1
STATUS_NUMERIC_ERROR = 2
STATUS_FALLBACK = 3


@dataclass(frozen=True)
class PMTParameters:
    sigma_ns: float = 3.5
    tau_ns: float = 8.0
    threshold_pe: float = 0.30
    noise_sigma_pe: float = 0.015


@dataclass(frozen=True)
class PMTEvent:
    seed: int
    event_id: int
    amplitude_pe: float
    peak_time_ns: float
    leading_threshold_time_ns: float
    t_dense_ns: np.ndarray
    a_dense_pe: np.ndarray
    t_samples_ns: np.ndarray
    a_samples_pe: np.ndarray
    params: PMTParameters


@dataclass(frozen=True)
class ReconstructionResult:
    mode_name: str
    mode_code: int
    status: int
    status_text: str
    t_est_ns: float
    amax_est_pe: float
    t_reco_ns: np.ndarray
    a_reco_pe: np.ndarray
    coeffs: tuple[float, ...]


def pmt_pulse(t_ns: np.ndarray, amplitude_pe: float, peak_time_ns: float, params: PMTParameters) -> np.ndarray:
    """Gaussian rising part + exponential tail, continuous at the match point."""
    sigma = max(params.sigma_ns, 1e-9)
    tau = max(params.tau_ns, 1e-9)
    x = t_ns - peak_time_ns
    t_match = sigma * sigma / tau
    c_match = math.exp(-0.5 * (t_match / sigma) ** 2)

    gaussian = amplitude_pe * np.exp(-0.5 * (x / sigma) ** 2)
    tail = amplitude_pe * c_match * np.exp(-(x - t_match) / tau)
    return np.where(x <= t_match, gaussian, tail)


def true_leading_threshold_time(amplitude_pe: float, peak_time_ns: float, params: PMTParameters) -> float:
    """Analytical leading threshold crossing for the Gaussian rising part."""
    threshold = params.threshold_pe
    if amplitude_pe <= threshold:
        return float("nan")
    return peak_time_ns - params.sigma_ns * math.sqrt(2.0 * math.log(amplitude_pe / threshold))


def generate_pmt_event(seed: int, sample_count: int, params: PMTParameters) -> PMTEvent:
    rng = np.random.default_rng(seed)
    amplitude = float(rng.uniform(0.8, 6.0))
    peak_time = float(rng.uniform(22.0, 30.0))
    leading_t = true_leading_threshold_time(amplitude, peak_time, params)

    t_min = peak_time - 18.0
    t_max = peak_time + 35.0
    t_dense = np.linspace(t_min, t_max, 1200)
    a_dense = pmt_pulse(t_dense, amplitude, peak_time, params)

    # Sparse samples are selected mainly on the rising edge, from just after threshold
    # to shortly before the peak. This matches the target use case: reconstructing the
    # leading edge from 2-3 or more samples.
    right_margin = max(0.35, 0.12 * params.sigma_ns)
    left_margin = max(0.15, 0.05 * params.sigma_ns)
    sample_start = leading_t + left_margin
    sample_stop = peak_time - right_margin
    if sample_stop <= sample_start:
        sample_start = peak_time - 0.75 * params.sigma_ns
        sample_stop = peak_time - right_margin

    # Slight random jitter prevents unrealistically perfect sample spacing, but remains
    # deterministic for a selected seed.
    base_samples = np.linspace(sample_start, sample_stop, sample_count)
    if sample_count > 2:
        jitter = rng.normal(0.0, 0.035, size=sample_count)
        jitter[0] = 0.0
        jitter[-1] = 0.0
        base_samples = np.sort(base_samples + jitter)

    clean_samples = pmt_pulse(base_samples, amplitude, peak_time, params)
    noisy_samples = clean_samples + rng.normal(0.0, params.noise_sigma_pe, size=sample_count)
    noisy_samples = np.clip(noisy_samples, 1e-6, None)

    return PMTEvent(
        seed=seed,
        event_id=seed,
        amplitude_pe=amplitude,
        peak_time_ns=peak_time,
        leading_threshold_time_ns=leading_t,
        t_dense_ns=t_dense,
        a_dense_pe=a_dense,
        t_samples_ns=base_samples,
        a_samples_pe=noisy_samples,
        params=params,
    )


def _safe_threshold_crossing_from_curve(t: np.ndarray, a: np.ndarray, threshold: float) -> float:
    above = a >= threshold
    idx = np.flatnonzero(above)
    if idx.size == 0:
        return float("nan")
    i = int(idx[0])
    if i == 0:
        return float(t[0])
    t1, t2 = float(t[i - 1]), float(t[i])
    a1, a2 = float(a[i - 1]), float(a[i])
    if abs(a2 - a1) < 1e-12:
        return t2
    return t1 + (threshold - a1) * (t2 - t1) / (a2 - a1)


def reconstruct_linear(event: PMTEvent) -> ReconstructionResult:
    t = event.t_samples_ns
    a = event.a_samples_pe
    threshold = event.params.threshold_pe
    if t.size < 2:
        raise ValueError("Interpolacja liniowa wymaga minimum 2 próbek.")
    # Fit to all selected samples; for two samples it is exactly the standard line.
    m, b = np.polyfit(t, a, 1)
    if abs(m) < 1e-12:
        return _fallback_result(event, "LIN - liniowa", STATUS_NUMERIC_ERROR, "Błąd: nachylenie bliskie zeru")
    t_grid = np.linspace(float(t.min()) - 4.0, float(t.max()) + 4.0, 500)
    a_reco = m * t_grid + b
    t_est = (threshold - b) / m
    amax_est = float(np.max(a))
    return ReconstructionResult(
        mode_name="LIN - liniowa",
        mode_code=MODE_CODES["LIN - liniowa"],
        status=STATUS_OK,
        status_text="OK",
        t_est_ns=float(t_est),
        amax_est_pe=amax_est,
        t_reco_ns=t_grid,
        a_reco_pe=a_reco,
        coeffs=(float(m), float(b)),
    )


def reconstruct_exp(event: PMTEvent) -> ReconstructionResult:
    t = event.t_samples_ns
    a = event.a_samples_pe
    threshold = event.params.threshold_pe
    if t.size < 3:
        raise ValueError("Interpolacja wykładnicza wymaga minimum 3 próbek.")
    if np.any(a <= 0):
        raise ValueError("Interpolacja EXP wymaga dodatnich amplitud.")
    k, log_c = np.polyfit(t, np.log(a), 1)
    if abs(k) < 1e-12:
        return _fallback_result(event, "EXP - wykładnicza", STATUS_NUMERIC_ERROR, "Błąd: k bliskie zeru")
    t_grid = np.linspace(float(t.min()) - 4.0, float(t.max()) + 4.0, 500)
    a_reco = np.exp(log_c + k * t_grid)
    t_est = (math.log(threshold) - log_c) / k
    amax_est = float(np.max(a_reco))
    return ReconstructionResult(
        mode_name="EXP - wykładnicza",
        mode_code=MODE_CODES["EXP - wykładnicza"],
        status=STATUS_OK,
        status_text="OK",
        t_est_ns=float(t_est),
        amax_est_pe=amax_est,
        t_reco_ns=t_grid,
        a_reco_pe=a_reco,
        coeffs=(float(k), float(log_c)),
    )


def reconstruct_log_gauss(event: PMTEvent) -> ReconstructionResult:
    t = event.t_samples_ns
    a = event.a_samples_pe
    threshold = event.params.threshold_pe
    if t.size < 3:
        raise ValueError("Interpolacja LOG/Gauss wymaga minimum 3 próbek.")
    if np.any(a <= 0):
        raise ValueError("Interpolacja LOG/Gauss wymaga dodatnich amplitud.")

    # Gaussian rising-edge fit in logarithmic domain:
    # ln(A) = c2*t^2 + c1*t + c0, c2 < 0.
    c2, c1, c0 = np.polyfit(t, np.log(a), 2)
    if c2 >= -1e-12:
        return _fallback_result(
            event,
            "LOG - logarytmiczna/Gauss",
            STATUS_FALLBACK,
            "Fallback: dopasowanie kwadratowe nie jest wklęsłe, użyto EXP",
        )

    peak_t = -c1 / (2.0 * c2)
    log_amax = c0 - (c1 * c1) / (4.0 * c2)
    amax_est = float(math.exp(log_amax))
    sigma_est = float(math.sqrt(-1.0 / (2.0 * c2)))

    t_grid = np.linspace(float(t.min()) - 4.0, max(float(t.max()) + 4.0, peak_t + 2.0), 600)
    a_reco = np.exp(c0 + c1 * t_grid + c2 * t_grid * t_grid)
    t_est = _safe_threshold_crossing_from_curve(t_grid, a_reco, threshold)

    return ReconstructionResult(
        mode_name="LOG - logarytmiczna/Gauss",
        mode_code=MODE_CODES["LOG - logarytmiczna/Gauss"],
        status=STATUS_OK,
        status_text=f"OK, sigma_est={sigma_est:.3f} ns, peak_est={peak_t:.3f} ns",
        t_est_ns=float(t_est),
        amax_est_pe=amax_est,
        t_reco_ns=t_grid,
        a_reco_pe=a_reco,
        coeffs=(float(c2), float(c1), float(c0), float(sigma_est), float(peak_t)),
    )


def _fallback_result(event: PMTEvent, mode_name: str, status: int, status_text: str) -> ReconstructionResult:
    exp_result = reconstruct_exp(event) if event.t_samples_ns.size >= 3 else reconstruct_linear(event)
    return ReconstructionResult(
        mode_name=mode_name,
        mode_code=MODE_CODES[mode_name],
        status=status,
        status_text=status_text,
        t_est_ns=exp_result.t_est_ns,
        amax_est_pe=exp_result.amax_est_pe,
        t_reco_ns=exp_result.t_reco_ns,
        a_reco_pe=exp_result.a_reco_pe,
        coeffs=exp_result.coeffs,
    )


def reconstruct(event: PMTEvent, mode_name: str) -> ReconstructionResult:
    functions: dict[str, Callable[[PMTEvent], ReconstructionResult]] = {
        "LIN - liniowa": reconstruct_linear,
        "EXP - wykładnicza": reconstruct_exp,
        "LOG - logarytmiczna/Gauss": reconstruct_log_gauss,
    }
    return functions[mode_name](event)


def q_format(value: float, fractional_bits: int, signed: bool, total_bits: int) -> int:
    """Convert float to fixed-point integer with saturation."""
    scale = 1 << fractional_bits
    raw = int(round(value * scale))
    if signed:
        lo = -(1 << (total_bits - 1))
        hi = (1 << (total_bits - 1)) - 1
    else:
        lo = 0
        hi = (1 << total_bits) - 1
    return max(lo, min(hi, raw))


def pad_samples(event: PMTEvent, n: int = 8) -> tuple[list[float], list[float]]:
    t_vals = list(map(float, event.t_samples_ns[:n]))
    a_vals = list(map(float, event.a_samples_pe[:n]))
    while len(t_vals) < n:
        t_vals.append(0.0)
        a_vals.append(0.0)
    return t_vals, a_vals


def true_trailing_threshold_time(amplitude_pe: float, peak_time_ns: float, params: PMTParameters) -> float:
    """Analytical trailing threshold crossing for the PMT model used in this app."""
    threshold = params.threshold_pe
    if amplitude_pe <= threshold:
        return float("nan")

    sigma = max(params.sigma_ns, 1e-9)
    tau = max(params.tau_ns, 1e-9)
    x_match = sigma * sigma / tau
    c_match = math.exp(-0.5 * (x_match / sigma) ** 2)
    amplitude_at_match = amplitude_pe * c_match

    # If the threshold is crossed before the Gaussian/tail match point, the second
    # crossing is still on the Gaussian part. Otherwise it lies on the exponential tail.
    if threshold >= amplitude_at_match:
        x_trailing = sigma * math.sqrt(2.0 * math.log(amplitude_pe / threshold))
    else:
        x_trailing = x_match + tau * math.log(amplitude_at_match / threshold)
    return peak_time_ns + x_trailing


def _select_legacy_samples(event: PMTEvent) -> tuple[list[float], list[float]]:
    """Return exactly three sample pairs for the legacy example_samples.csv layout.

    The old FPGA/Python generator stores only t1/A1, t2/A2 and t3/A3.
    For more than three GUI samples we keep three representative points from the
    selected rising-edge window: first, middle and last. For two-sample LIN tests
    the third pair is padded with zeros.
    """
    t = list(map(float, event.t_samples_ns))
    a = list(map(float, event.a_samples_pe))
    n = len(t)

    if n >= 3:
        if n == 3:
            idx = [0, 1, 2]
        else:
            idx = [0, n // 2, n - 1]
        return [t[i] for i in idx], [a[i] for i in idx]

    while len(t) < 3:
        t.append(0.0)
        a.append(0.0)
    return t[:3], a[:3]


def build_csv_row(event: PMTEvent, result: ReconstructionResult) -> dict[str, int | float]:
    """Build a row compatible with the legacy example_samples.csv generator.

    Exact column order:
    event_id,t1,A1,t2,A2,t3,A3,true_t0,true_amax,sigma_ns,tau_ns,
    threshold,charge,true_t_leading,true_t_trailing,true_tot
    """
    t_vals, a_vals = _select_legacy_samples(event)
    true_trailing = true_trailing_threshold_time(event.amplitude_pe, event.peak_time_ns, event.params)
    true_tot = true_trailing - event.leading_threshold_time_ns

    return {
        "event_id": int(event.event_id),
        "t1": float(t_vals[0]),
        "A1": float(a_vals[0]),
        "t2": float(t_vals[1]),
        "A2": float(a_vals[1]),
        "t3": float(t_vals[2]),
        "A3": float(a_vals[2]),
        "true_t0": float(event.peak_time_ns),
        "true_amax": float(event.amplitude_pe),
        "sigma_ns": float(event.params.sigma_ns),
        "tau_ns": float(event.params.tau_ns),
        "threshold": float(event.params.threshold_pe),
        "charge": float(event.amplitude_pe),
        "true_t_leading": float(event.leading_threshold_time_ns),
        "true_t_trailing": float(true_trailing),
        "true_tot": float(true_tot),
    }


class LeadingEdgeApp(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("Leading Edge PMT Tester - CSV for FPGA")
        self.geometry("1280x820")
        self.minsize(1100, 720)

        self.current_event: PMTEvent | None = None
        self.current_result: ReconstructionResult | None = None

        self._build_ui()
        self._log("Aplikacja uruchomiona.")
        self._log("Wybierz tryb, liczbę próbek i seed, a następnie kliknij 'Generuj i rekonstruuj'.")
        self._log("Eksport CSV używa formatu zgodnego ze starym example_samples.csv: t1,A1,t2,A2,t3,A3 + wartości referencyjne.")

    def _build_ui(self) -> None:
        self.columnconfigure(0, weight=0)
        self.columnconfigure(1, weight=1)
        self.rowconfigure(0, weight=1)

        left = ttk.Frame(self, padding=10)
        left.grid(row=0, column=0, sticky="nsw")
        left.columnconfigure(1, weight=1)

        plot_frame = ttk.Frame(self, padding=(0, 10, 10, 10))
        plot_frame.grid(row=0, column=1, sticky="nsew")
        plot_frame.columnconfigure(0, weight=1)
        plot_frame.rowconfigure(0, weight=1)
        plot_frame.rowconfigure(1, weight=0)

        controls = ttk.LabelFrame(left, text="Parametry testu", padding=10)
        controls.grid(row=0, column=0, columnspan=2, sticky="ew")
        controls.columnconfigure(1, weight=1)

        ttk.Label(controls, text="Tryb interpolacji:").grid(row=0, column=0, sticky="w", pady=4)
        self.mode_var = tk.StringVar(value="LIN - liniowa")
        mode_box = ttk.Combobox(controls, textvariable=self.mode_var, values=list(MODE_CODES.keys()), state="readonly", width=24)
        mode_box.grid(row=0, column=1, sticky="ew", pady=4)

        ttk.Label(controls, text="Liczba próbek:").grid(row=1, column=0, sticky="w", pady=4)
        self.samples_var = tk.IntVar(value=3)
        samples = ttk.Spinbox(controls, from_=2, to=8, textvariable=self.samples_var, width=8)
        samples.grid(row=1, column=1, sticky="ew", pady=4)

        ttk.Label(controls, text="Seed PMT:").grid(row=2, column=0, sticky="w", pady=4)
        self.seed_var = tk.IntVar(value=1234)
        seed_entry = ttk.Entry(controls, textvariable=self.seed_var, width=12)
        seed_entry.grid(row=2, column=1, sticky="ew", pady=4)

        ttk.Separator(controls).grid(row=3, column=0, columnspan=2, sticky="ew", pady=8)

        ttk.Label(controls, text="σ Gaussa [ns]:").grid(row=4, column=0, sticky="w", pady=4)
        self.sigma_var = tk.DoubleVar(value=3.5)
        ttk.Entry(controls, textvariable=self.sigma_var, width=12).grid(row=4, column=1, sticky="ew", pady=4)

        ttk.Label(controls, text="τ ogona [ns]:").grid(row=5, column=0, sticky="w", pady=4)
        self.tau_var = tk.DoubleVar(value=8.0)
        ttk.Entry(controls, textvariable=self.tau_var, width=12).grid(row=5, column=1, sticky="ew", pady=4)

        ttk.Label(controls, text="Próg V0 [p.e.]:").grid(row=6, column=0, sticky="w", pady=4)
        self.threshold_var = tk.DoubleVar(value=0.30)
        ttk.Entry(controls, textvariable=self.threshold_var, width=12).grid(row=6, column=1, sticky="ew", pady=4)

        ttk.Label(controls, text="Szum σ [p.e.]:").grid(row=7, column=0, sticky="w", pady=4)
        self.noise_var = tk.DoubleVar(value=0.015)
        ttk.Entry(controls, textvariable=self.noise_var, width=12).grid(row=7, column=1, sticky="ew", pady=4)

        buttons = ttk.Frame(left, padding=(0, 10, 0, 10))
        buttons.grid(row=1, column=0, columnspan=2, sticky="ew")
        buttons.columnconfigure(0, weight=1)

        ttk.Button(buttons, text="Generuj i rekonstruuj", command=self.on_generate).grid(row=0, column=0, sticky="ew", pady=4)
        ttk.Button(buttons, text="Zapisz CSV dla FPGA", command=self.on_save_csv).grid(row=1, column=0, sticky="ew", pady=4)
        ttk.Button(buttons, text="Następny seed", command=self.on_next_seed).grid(row=2, column=0, sticky="ew", pady=4)
        ttk.Button(buttons, text="Wyczyść logi", command=self.on_clear_logs).grid(row=3, column=0, sticky="ew", pady=4)

        summary = ttk.LabelFrame(left, text="Wynik", padding=10)
        summary.grid(row=2, column=0, columnspan=2, sticky="new", pady=(0, 10))
        summary.columnconfigure(1, weight=1)

        self.summary_vars = {
            "mode": tk.StringVar(value="-"),
            "t_ref": tk.StringVar(value="-"),
            "t_est": tk.StringVar(value="-"),
            "err": tk.StringVar(value="-"),
            "amp": tk.StringVar(value="-"),
            "status": tk.StringVar(value="-"),
        }
        labels = [
            ("Tryb:", "mode"),
            ("t_ref leading [ns]:", "t_ref"),
            ("t_est leading [ns]:", "t_est"),
            ("Błąd [ns]:", "err"),
            ("Amax est [p.e.]:", "amp"),
            ("Status:", "status"),
        ]
        for r, (label, key) in enumerate(labels):
            ttk.Label(summary, text=label).grid(row=r, column=0, sticky="w", pady=2)
            ttk.Label(summary, textvariable=self.summary_vars[key]).grid(row=r, column=1, sticky="w", pady=2)

        logs_frame = ttk.LabelFrame(left, text="Konsola logów", padding=8)
        logs_frame.grid(row=3, column=0, columnspan=2, sticky="nsew")
        left.rowconfigure(3, weight=1)
        logs_frame.columnconfigure(0, weight=1)
        logs_frame.rowconfigure(0, weight=1)

        self.log_text = tk.Text(logs_frame, width=48, height=16, wrap="word", state="disabled")
        self.log_text.grid(row=0, column=0, sticky="nsew")
        scroll = ttk.Scrollbar(logs_frame, command=self.log_text.yview)
        scroll.grid(row=0, column=1, sticky="ns")
        self.log_text.configure(yscrollcommand=scroll.set)

        self.figure = Figure(figsize=(8, 5.2), dpi=100)
        self.ax = self.figure.add_subplot(111)
        self.ax.set_title("Rekonstrukcja zbocza PMT")
        self.ax.set_xlabel("czas [ns]")
        self.ax.set_ylabel("amplituda [p.e.]")
        self.ax.grid(True, alpha=0.35)

        self.canvas = FigureCanvasTkAgg(self.figure, master=plot_frame)
        self.canvas.draw()
        self.canvas.get_tk_widget().grid(row=0, column=0, sticky="nsew")
        toolbar = NavigationToolbar2Tk(self.canvas, plot_frame, pack_toolbar=False)
        toolbar.update()
        toolbar.grid(row=1, column=0, sticky="ew")

    def _read_params(self) -> PMTParameters:
        sigma = float(self.sigma_var.get())
        tau = float(self.tau_var.get())
        threshold = float(self.threshold_var.get())
        noise = float(self.noise_var.get())
        if sigma <= 0 or tau <= 0:
            raise ValueError("Parametry sigma i tau muszą być dodatnie.")
        if threshold <= 0:
            raise ValueError("Próg V0 musi być dodatni.")
        if noise < 0:
            raise ValueError("Szum nie może być ujemny.")
        return PMTParameters(sigma_ns=sigma, tau_ns=tau, threshold_pe=threshold, noise_sigma_pe=noise)

    def _log(self, message: str) -> None:
        timestamp = datetime.now().strftime("%H:%M:%S")
        self.log_text.configure(state="normal")
        self.log_text.insert("end", f"[{timestamp}] {message}\n")
        self.log_text.see("end")
        self.log_text.configure(state="disabled")

    def on_generate(self) -> None:
        try:
            sample_count = int(self.samples_var.get())
            if sample_count < 2 or sample_count > 8:
                raise ValueError("Liczba próbek musi być z zakresu 2..8.")
            mode = self.mode_var.get()
            if mode != "LIN - liniowa" and sample_count < 3:
                raise ValueError("Tryby EXP i LOG wymagają minimum 3 próbek.")

            seed = int(self.seed_var.get())
            params = self._read_params()
            event = generate_pmt_event(seed=seed, sample_count=sample_count, params=params)
            result = reconstruct(event, mode)

            self.current_event = event
            self.current_result = result
            self._update_summary(event, result)
            self._draw_plot(event, result)

            err = result.t_est_ns - event.leading_threshold_time_ns
            self._log(
                f"Wygenerowano event seed={seed}, mode={mode}, samples={sample_count}, "
                f"t_ref={event.leading_threshold_time_ns:.4f} ns, t_est={result.t_est_ns:.4f} ns, err={err:+.4f} ns."
            )
            if result.status != STATUS_OK:
                self._log(f"Status rekonstrukcji: {result.status_text}")
        except Exception as exc:
            self._log(f"BŁĄD: {exc}")
            self._log(traceback.format_exc().splitlines()[-1])
            messagebox.showerror("Błąd", str(exc))

    def _update_summary(self, event: PMTEvent, result: ReconstructionResult) -> None:
        err = result.t_est_ns - event.leading_threshold_time_ns
        self.summary_vars["mode"].set(result.mode_name)
        self.summary_vars["t_ref"].set(f"{event.leading_threshold_time_ns:.5f}")
        self.summary_vars["t_est"].set(f"{result.t_est_ns:.5f}")
        self.summary_vars["err"].set(f"{err:+.5f}")
        self.summary_vars["amp"].set(f"{result.amax_est_pe:.5f}")
        self.summary_vars["status"].set(f"{result.status} / {result.status_text}")

    def _draw_plot(self, event: PMTEvent, result: ReconstructionResult) -> None:
        self.ax.clear()
        self.ax.plot(event.t_dense_ns, event.a_dense_pe, label="rzeczywisty impuls PMT")
        self.ax.plot(result.t_reco_ns, result.a_reco_pe, linestyle="--", label="zrekonstruowane zbocze")
        self.ax.scatter(event.t_samples_ns, event.a_samples_pe, marker="o", label="próbki wejściowe")
        self.ax.axhline(event.params.threshold_pe, linestyle=":", label="próg V0")
        self.ax.axvline(event.leading_threshold_time_ns, linestyle=":", label="t_ref leading")
        self.ax.axvline(result.t_est_ns, linestyle="--", label="t_est leading")
        self.ax.axvline(event.peak_time_ns, linestyle="-.", label="t_ref peak")
        self.ax.set_title(f"Rekonstrukcja zbocza PMT | seed={event.seed} | {result.mode_name}")
        self.ax.set_xlabel("czas [ns]")
        self.ax.set_ylabel("amplituda [p.e.]")
        self.ax.grid(True, alpha=0.35)
        self.ax.legend(loc="best")
        self.figure.tight_layout()
        self.canvas.draw_idle()

    def on_save_csv(self) -> None:
        if self.current_event is None or self.current_result is None:
            messagebox.showwarning("Brak danych", "Najpierw wygeneruj i zrekonstruuj impuls.")
            return
        default_name = f"fpga_input_seed_{self.current_event.seed}_{self.current_result.mode_code}.csv"
        path = filedialog.asksaveasfilename(
            title="Zapisz CSV dla FPGA",
            defaultextension=".csv",
            initialfile=default_name,
            filetypes=[("CSV", "*.csv"), ("Wszystkie pliki", "*.*")],
        )
        if not path:
            return
        try:
            row = build_csv_row(self.current_event, self.current_result)
            with open(path, "w", newline="", encoding="utf-8") as f:
                writer = csv.DictWriter(f, fieldnames=list(row.keys()))
                writer.writeheader()
                writer.writerow(row)
            if int(self.current_event.t_samples_ns.size) > 3:
                self._log("CSV legacy obsługuje 3 próbki, więc zapisano reprezentatywnie: pierwszą, środkową i ostatnią próbkę.")
            elif int(self.current_event.t_samples_ns.size) < 3:
                self._log("CSV legacy wymaga kolumn t3/A3, więc brakującą trzecią próbkę uzupełniono zerami.")
            self._log(f"Zapisano CSV zgodny z example_samples.csv: {Path(path).name}")
            messagebox.showinfo("Zapisano", f"Plik CSV zapisany:\n{path}")
        except Exception as exc:
            self._log(f"BŁĄD zapisu CSV: {exc}")
            messagebox.showerror("Błąd zapisu", str(exc))

    def on_next_seed(self) -> None:
        try:
            self.seed_var.set(int(self.seed_var.get()) + 1)
        except Exception:
            self.seed_var.set(1)
        self.on_generate()

    def on_clear_logs(self) -> None:
        self.log_text.configure(state="normal")
        self.log_text.delete("1.0", "end")
        self.log_text.configure(state="disabled")
        self._log("Logi wyczyszczone.")


def main() -> None:
    app = LeadingEdgeApp()
    app.mainloop()


if __name__ == "__main__":
    main()
