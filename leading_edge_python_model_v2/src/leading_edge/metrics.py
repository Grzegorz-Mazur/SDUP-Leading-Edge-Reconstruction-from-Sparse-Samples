"""
Metrics and tabular summaries for reconstruction results.
"""

from __future__ import annotations

import math

import pandas as pd

from .models import ReconstructionResult


def build_summary_table(results: list[ReconstructionResult]) -> pd.DataFrame:
    """
    Convert reconstruction results to a pandas DataFrame.
    """
    rows: list[dict[str, object]] = []

    for result in results:
        rows.append(
            {
                "event_id": result.event_id,
                "method": result.method,
                "t0_est": result.t0_est,
                "amax_est": result.amax_est,
                "true_t0": result.true_t0,
                "true_amax": result.true_amax,
                "t0_error": result.t0_error,
                "amax_error": result.amax_error,
                "status": result.status,
            }
        )

    return pd.DataFrame(rows)


def rmse(values: list[float | None]) -> float:
    """
    Return root mean square error for a list of errors.
    """
    clean_values = [
        value
        for value in values
        if value is not None and not math.isnan(value)
    ]

    if not clean_values:
        return float("nan")

    return math.sqrt(sum(value**2 for value in clean_values) / len(clean_values))


def rmse_by_method(results: list[ReconstructionResult]) -> dict[str, float]:
    """
    Return t0 RMSE grouped by reconstruction method.
    """
    methods = sorted({result.method for result in results})
    output: dict[str, float] = {}

    for method in methods:
        errors = [
            result.t0_error
            for result in results
            if result.method == method and result.t0_error is not None
        ]
        output[method] = rmse(errors)

    return output
