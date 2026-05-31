#!/usr/bin/env python3
"""
Leading Edge Reconstruction from Sparse PMT Samples.

This script compares three reconstruction methods:
- linear
- exponential
- logarithmic / Gaussian-domain

Input sources:
- PMT synthetic generator
- hardcoded Python list
- CSV file

All time values are in ns.
All amplitudes are in arbitrary units, for example p.e. or normalized mV.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import random

import matplotlib.pyplot as plt

from src.leading_edge.data import (
    generate_pmt_events,
    get_list_events,
    load_events_from_csv,
    save_events_to_csv,
)
from src.leading_edge.interpolation import reconstruct_all_methods
from src.leading_edge.metrics import build_summary_table, rmse_by_method
from src.leading_edge.plotting import (
    create_error_summary_plot,
    create_method_comparison_plot,
    create_reconstructed_signal_plots,
    create_tot_comparison_plot,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Leading edge reconstruction Python golden model."
    )

    parser.add_argument(
        "--source",
        choices=["pmt", "list", "csv"],
        default="pmt",
        help="Input data source.",
    )

    parser.add_argument(
        "--csv",
        type=str,
        default="data/example_samples.csv",
        help="CSV file path used when --source csv is selected.",
    )

    parser.add_argument(
        "--events",
        type=int,
        default=20,
        help="Number of synthetic PMT events.",
    )

    parser.add_argument(
        "--seed",
        type=int,
        default=None,
        help=(
            "Random seed for reproducible PMT data. "
            "If omitted, a new random seed is generated."
        ),
    )

    parser.add_argument(
        "--noise",
        type=float,
        default=0.02,
        help="Relative amplitude noise level for PMT synthetic data.",
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

    parser.add_argument(
        "--save-example-csv",
        action="store_true",
        help="Generate and save an example CSV file using the PMT model.",
    )

    parser.add_argument(
        "--max-plotted-events",
        type=int,
        default=3,
        help="Number of individual event plots to create.",
    )

    return parser.parse_args()


def resolve_seed(seed: int | None) -> int:
    """
    Return a deterministic seed.

    If the user does not provide --seed, generate a random seed and print it.
    This gives random behavior by default while preserving reproducibility.
    """
    if seed is not None:
        print(f"Using fixed PMT seed: {seed}")
        return seed

    generated_seed = random.SystemRandom().randint(0, 2**32 - 1)
    print(f"Random PMT seed selected: {generated_seed}")
    return generated_seed


def main() -> None:
    args = parse_args()

    pmt_seed = resolve_seed(args.seed)

    if args.save_example_csv:
        example_events = generate_pmt_events(
            n_events=args.events,
            seed=pmt_seed,
            noise_std=args.noise,
            sigma_ns=args.sigma,
            tau_ns=args.tau,
            threshold=args.threshold,
        )
        save_events_to_csv(example_events, Path(args.csv))
        print(f"Example CSV saved to: {args.csv}")

    if args.source == "pmt":
        events = generate_pmt_events(
            n_events=args.events,
            seed=pmt_seed,
            noise_std=args.noise,
            sigma_ns=args.sigma,
            tau_ns=args.tau,
            threshold=args.threshold,
        )
    elif args.source == "list":
        events = get_list_events()
    elif args.source == "csv":
        events = load_events_from_csv(Path(args.csv))
    else:
        raise ValueError(f"Unsupported source: {args.source}")

    results = reconstruct_all_methods(events)
    summary = build_summary_table(results)

    print("\n=== Reconstruction results ===")
    print(summary.to_string(index=False, float_format=lambda value: f"{value:10.5f}"))

    print("\n=== t0 RMSE by method ===")
    for method, value in rmse_by_method(results).items():
        print(f"{method:12s}: {value:.6f} ns")

    # Create all figures first and show all windows at once.
    create_reconstructed_signal_plots(
        events=events,
        results=results,
        max_events=args.max_plotted_events,
    )
    create_method_comparison_plot(results)
    create_error_summary_plot(results)
    create_tot_comparison_plot(events)

    plt.show()


if __name__ == "__main__":
    main()
