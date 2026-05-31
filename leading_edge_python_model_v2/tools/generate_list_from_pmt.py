#!/usr/bin/env python3
"""
Generate a Python list of SampleEvent objects from the PMT model.

The output can be copied directly into get_list_events() in:
src/leading_edge/data.py
"""

from __future__ import annotations

import argparse
from pathlib import Path
import random
import sys

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))

from src.leading_edge.data import generate_pmt_events


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate hardcoded Python list vectors from the PMT model."
    )

    parser.add_argument(
        "--events",
        type=int,
        default=5,
        help="Number of PMT events to generate.",
    )

    parser.add_argument(
        "--seed",
        type=int,
        default=None,
        help="Fixed PMT seed. If omitted, a random seed is generated.",
    )

    parser.add_argument(
        "--noise",
        type=float,
        default=0.0,
        help="Relative amplitude noise level.",
    )

    parser.add_argument(
        "--sigma",
        type=float,
        default=4.0,
        help="Gaussian width sigma in ns.",
    )

    parser.add_argument(
        "--tau",
        type=float,
        default=8.0,
        help="Exponential decay constant tau in ns.",
    )

    parser.add_argument(
        "--threshold",
        type=float,
        default=0.3,
        help="Discriminator threshold.",
    )

    return parser.parse_args()


def resolve_seed(seed: int | None) -> int:
    """
    Return fixed or randomly generated seed.
    """
    if seed is not None:
        return seed
    return random.SystemRandom().randint(0, 2**32 - 1)


def _fmt(value: float | None) -> str:
    """
    Format optional float for Python code output.
    """
    if value is None:
        return "None"
    return f"{value:.6f}"


def main() -> None:
    args = parse_args()
    seed = resolve_seed(args.seed)

    events = generate_pmt_events(
        n_events=args.events,
        seed=seed,
        noise_std=args.noise,
        sigma_ns=args.sigma,
        tau_ns=args.tau,
        threshold=args.threshold,
    )

    print(f"# Generated with seed={seed}, events={args.events}, noise={args.noise}")
    print("return [")
    for event in events:
        print(
            "    SampleEvent("
            f"{event.event_id}, "
            f"{_fmt(event.t1)}, {_fmt(event.a1)}, "
            f"{_fmt(event.t2)}, {_fmt(event.a2)}, "
            f"{_fmt(event.t3)}, {_fmt(event.a3)}, "
            f"{_fmt(event.true_t0)}, {_fmt(event.true_amax)}, "
            f"{_fmt(event.sigma_ns)}, {_fmt(event.tau_ns)}, "
            f"{_fmt(event.threshold)}, {_fmt(event.charge)}, "
            f"{_fmt(event.true_t_leading)}, {_fmt(event.true_t_trailing)}, "
            f"{_fmt(event.true_tot)}"
            "),"
        )
    print("]")


if __name__ == "__main__":
    main()
