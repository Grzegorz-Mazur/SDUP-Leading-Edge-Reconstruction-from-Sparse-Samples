"""
Data sources for the leading edge reconstruction model.

Supported input sources:
1. Synthetic PMT-like generator.
2. Hardcoded Python list.
3. CSV file.

CSV data is useful for exporting the same vectors to Python, RTL testbenches,
and later PYNQ notebooks.
"""

from __future__ import annotations

from pathlib import Path
import csv
import random

from .models import SampleEvent
from .pmt_model import PMTParameters, sample_relative_to_peak, threshold_crossings, safe_positive


def _add_noise(value: float, rng: random.Random, noise_std: float) -> float:
    """
    Add multiplicative Gaussian noise and prevent non-positive amplitudes.
    """
    if noise_std <= 0.0:
        return safe_positive(value)
    return safe_positive(value * (1.0 + rng.gauss(0.0, noise_std)))


def generate_pmt_events(
    n_events: int = 20,
    seed: int | None = None,
    noise_std: float = 0.02,
    sigma_ns: float = 4.0,
    tau_ns: float = 8.0,
    threshold: float = 0.3,
) -> list[SampleEvent]:
    """
    Generate synthetic sparse samples from the compact PMT model.

    The sparse samples are placed on the rising Gaussian section before the
    pulse peak. The full reference curve still contains the exponential tail.
    """
    rng = random.Random(seed)
    params = PMTParameters(
        sigma_ns=sigma_ns,
        tau_ns=tau_ns,
        threshold=threshold,
        r_tilde=1.0,
    )

    events: list[SampleEvent] = []

    for event_id in range(n_events):
        t_peak = rng.uniform(18.0, 25.0)

        # In this simplified model charge is numerically equal to peak amplitude
        # because r_tilde = 1.0.
        charge = rng.uniform(0.7, 6.0)
        true_amax = charge * params.r_tilde

        # Three sparse samples on the rising edge.
        offsets = sorted(
            [
                -rng.uniform(6.0, 8.5),
                -rng.uniform(3.0, 5.0),
                -rng.uniform(0.8, 2.0),
            ]
        )

        t1, a1 = sample_relative_to_peak(t_peak, charge, params, offsets[0])
        t2, a2 = sample_relative_to_peak(t_peak, charge, params, offsets[1])
        t3, a3 = sample_relative_to_peak(t_peak, charge, params, offsets[2])

        a1 = _add_noise(a1, rng, noise_std)
        a2 = _add_noise(a2, rng, noise_std)
        a3 = _add_noise(a3, rng, noise_std)

        crossing_data = threshold_crossings(t_peak, charge, params)
        if crossing_data is None:
            true_t_leading = None
            true_t_trailing = None
            true_tot = None
        else:
            true_t_leading, true_t_trailing, true_tot = crossing_data

        events.append(
            SampleEvent(
                event_id=event_id,
                t1=t1,
                a1=a1,
                t2=t2,
                a2=a2,
                t3=t3,
                a3=a3,
                true_t0=t_peak,
                true_amax=true_amax,
                sigma_ns=params.sigma_ns,
                tau_ns=params.tau_ns,
                threshold=params.threshold,
                charge=charge,
                true_t_leading=true_t_leading,
                true_t_trailing=true_t_trailing,
                true_tot=true_tot,
            )
        )

    return events


def get_list_events() -> list[SampleEvent]:
    """
    Return deterministic hardcoded test vectors generated from the PMT model.

    To replace this list with new PMT-generated vectors, run:
        python tools/generate_list_from_pmt.py --events 5 --seed 7 --noise 0.0

    Then paste the printed list here.
    """
    return [
        SampleEvent(0, 13.441488, 1.248941, 15.903052, 3.651062, 18.009984, 5.065083, 18.284813, 5.414626, 4.000000, 8.000000, 0.300000, 5.414626, 9.791473, 40.914891, 31.123418),
        SampleEvent(1, 15.622099, 1.032775, 17.450997, 1.957657, 20.473995, 2.620367, 20.610828, 2.626787, 4.000000, 8.000000, 0.300000, 2.626787, 12.234282, 37.524981, 25.290699),
        SampleEvent(2, 13.400637, 0.958252, 15.813172, 2.797585, 18.161888, 4.307609, 18.762445, 4.705626, 4.000000, 8.000000, 0.300000, 4.705626, 10.168912, 39.555910, 29.386998),
        SampleEvent(3, 13.262626, 0.581050, 15.566904, 1.844554, 17.892898, 2.811370, 18.805289, 3.129167, 4.000000, 8.000000, 0.300000, 3.129167, 11.956358, 37.618413, 25.662055),
        SampleEvent(4, 15.480329, 0.772686, 18.522173, 3.071598, 20.205404, 4.120738, 21.007225, 4.652842, 4.000000, 8.000000, 0.300000, 4.652842, 12.445938, 41.215572, 28.769634),
    ]


def load_events_from_csv(path: Path) -> list[SampleEvent]:
    """
    Load sparse events from a CSV file.

    Required columns:
        event_id,t1,A1,t2,A2

    Optional columns:
        t3,A3,true_t0,true_amax,sigma_ns,tau_ns,threshold,charge,
        true_t_leading,true_t_trailing,true_tot
    """
    if not path.exists():
        raise FileNotFoundError(
            f"CSV file not found: {path}. "
            "Run with --save-example-csv first or provide your own file."
        )

    events: list[SampleEvent] = []

    with path.open("r", newline="") as file:
        reader = csv.DictReader(file)

        for row in reader:
            events.append(
                SampleEvent(
                    event_id=int(row["event_id"]),
                    t1=float(row["t1"]),
                    a1=float(row["A1"]),
                    t2=float(row["t2"]),
                    a2=float(row["A2"]),
                    t3=_optional_float(row.get("t3")),
                    a3=_optional_float(row.get("A3")),
                    true_t0=_optional_float(row.get("true_t0")),
                    true_amax=_optional_float(row.get("true_amax")),
                    sigma_ns=_optional_float(row.get("sigma_ns")),
                    tau_ns=_optional_float(row.get("tau_ns")),
                    threshold=_optional_float(row.get("threshold")),
                    charge=_optional_float(row.get("charge")),
                    true_t_leading=_optional_float(row.get("true_t_leading")),
                    true_t_trailing=_optional_float(row.get("true_t_trailing")),
                    true_tot=_optional_float(row.get("true_tot")),
                )
            )

    return events


def save_events_to_csv(events: list[SampleEvent], path: Path) -> None:
    """
    Save events to a CSV file compatible with load_events_from_csv().
    """
    path.parent.mkdir(parents=True, exist_ok=True)

    with path.open("w", newline="") as file:
        fieldnames = [
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
        writer = csv.DictWriter(file, fieldnames=fieldnames)
        writer.writeheader()

        for event in events:
            writer.writerow(
                {
                    "event_id": event.event_id,
                    "t1": event.t1,
                    "A1": event.a1,
                    "t2": event.t2,
                    "A2": event.a2,
                    "t3": event.t3,
                    "A3": event.a3,
                    "true_t0": event.true_t0,
                    "true_amax": event.true_amax,
                    "sigma_ns": event.sigma_ns,
                    "tau_ns": event.tau_ns,
                    "threshold": event.threshold,
                    "charge": event.charge,
                    "true_t_leading": event.true_t_leading,
                    "true_t_trailing": event.true_t_trailing,
                    "true_tot": event.true_tot,
                }
            )


def _optional_float(value: str | None) -> float | None:
    """
    Convert optional CSV field to float.
    """
    if value is None or value == "":
        return None
    return float(value)
