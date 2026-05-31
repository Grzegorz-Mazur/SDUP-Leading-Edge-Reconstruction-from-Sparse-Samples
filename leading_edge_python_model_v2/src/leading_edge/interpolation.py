"""
Interpolation / reconstruction algorithms.

The goal is to estimate:
- t0_est: pulse peak time or corrected timing estimate
- amax_est: estimated peak amplitude

The functions are written as a Python golden model. Later they can be simplified,
quantized, or approximated by LUT/CORDIC blocks for FPGA implementation.
"""

from __future__ import annotations

import math

from .models import ReconstructionResult, SampleEvent


_EPS = 1e-12


def reconstruct_linear(event: SampleEvent) -> ReconstructionResult:
    """
    Linear extrapolation using two samples.

    Formula:
        t_cross = t1 - A1 * (t2 - t1) / (A2 - A1)

    This is a low-cost FPGA baseline. It estimates a baseline/threshold-related
    crossing time, not a true Gaussian peak. Therefore it is expected to be less
    accurate than the logarithmic method when compared against true_t0.
    """
    if event.a1 <= 0.0 or event.a2 <= event.a1:
        return _error_result(event, "linear", "error: expected A2 > A1 > 0")

    if abs(event.t2 - event.t1) < _EPS:
        return _error_result(event, "linear", "error: duplicated sample time")

    slope = (event.a2 - event.a1) / (event.t2 - event.t1)
    if abs(slope) < _EPS:
        return _error_result(event, "linear", "error: slope too small")

    t0_est = event.t1 - event.a1 / slope
    amax_est = _max_available_amplitude(event)

    return ReconstructionResult(
        event_id=event.event_id,
        method="linear",
        t0_est=t0_est,
        amax_est=amax_est,
        status="valid",
        true_t0=event.true_t0,
        true_amax=event.true_amax,
    )


def reconstruct_exponential(event: SampleEvent) -> ReconstructionResult:
    """
    Exponential-domain reconstruction using three samples.

    The sparse samples are modeled locally as:
        A(t) = K * exp(t / tau)

    From two samples:
        tau_est = (t3 - t2) / ln(A3 / A2)

    With a discriminator threshold:
        t_cross = t1 - tau_est * ln(A1 / threshold)

    This method is included as a hardware-relevant comparison because it maps to
    logarithm/LUT operations. For the true Gaussian rising edge, it is usually
    less physically accurate than the logarithmic Gaussian-domain method.
    """
    if not _has_three_samples(event):
        return _error_result(event, "exponential", "error: missing t3/A3")

    if event.threshold is None or event.threshold <= 0.0:
        return _error_result(event, "exponential", "error: missing positive threshold")

    if event.a1 <= 0.0 or event.a2 <= 0.0 or event.a3 <= 0.0:
        return _error_result(event, "exponential", "error: amplitudes must be positive")

    if not (event.a3 > event.a2 > event.a1):
        return _error_result(event, "exponential", "error: expected A3 > A2 > A1")

    denominator = math.log(event.a3 / event.a2)
    if abs(denominator) < _EPS:
        return _error_result(event, "exponential", "error: log denominator too small")

    tau_est = (event.t3 - event.t2) / denominator
    t_cross = event.t1 - tau_est * math.log(event.a1 / event.threshold)

    # Conservative sparse-sample amplitude estimate.
    amax_est = event.a3

    return ReconstructionResult(
        event_id=event.event_id,
        method="exponential",
        t0_est=t_cross,
        amax_est=amax_est,
        status="valid",
        true_t0=event.true_t0,
        true_amax=event.true_amax,
    )


def reconstruct_logarithmic(event: SampleEvent) -> ReconstructionResult:
    """
    Logarithmic / Gaussian-domain reconstruction using three samples.

    For a Gaussian rising edge:
        A(t) = Amax * exp(-0.5 * ((t - t0) / sigma)^2)

    After logarithm:
        ln(A) = c2*t^2 + c1*t + c0

    The peak time is the vertex:
        t0 = -c1 / (2*c2)

    The peak amplitude is:
        Amax = exp(ln(A(t0)))
    """
    if not _has_three_samples(event):
        return _error_result(event, "logarithmic", "error: missing t3/A3")

    if event.a1 <= 0.0 or event.a2 <= 0.0 or event.a3 <= 0.0:
        return _error_result(event, "logarithmic", "error: amplitudes must be positive")

    t_values = [event.t1, event.t2, event.t3]
    y_values = [math.log(event.a1), math.log(event.a2), math.log(event.a3)]

    try:
        c2, c1, c0 = _quadratic_fit_three_points(t_values, y_values)
    except ZeroDivisionError:
        return _error_result(event, "logarithmic", "error: degenerated time samples")

    if abs(c2) < _EPS:
        return _error_result(event, "logarithmic", "error: quadratic coefficient too small")

    if c2 >= 0.0:
        return _error_result(event, "logarithmic", "error: not a concave Gaussian fit")

    t0_est = -c1 / (2.0 * c2)
    log_amax_est = c2 * t0_est**2 + c1 * t0_est + c0
    amax_est = math.exp(log_amax_est)

    return ReconstructionResult(
        event_id=event.event_id,
        method="logarithmic",
        t0_est=t0_est,
        amax_est=amax_est,
        status="valid",
        true_t0=event.true_t0,
        true_amax=event.true_amax,
    )


def reconstruct_all_methods(events: list[SampleEvent]) -> list[ReconstructionResult]:
    """
    Run all reconstruction methods for all events.
    """
    results: list[ReconstructionResult] = []

    for event in events:
        results.append(reconstruct_linear(event))
        results.append(reconstruct_exponential(event))
        results.append(reconstruct_logarithmic(event))

    return results


def _quadratic_fit_three_points(
    t_values: list[float],
    y_values: list[float],
) -> tuple[float, float, float]:
    """
    Fit y = c2*t^2 + c1*t + c0 through exactly three points.

    This implementation avoids making NumPy mandatory inside the algorithm
    module, which helps when translating the logic to RTL-oriented arithmetic.
    """
    x1, x2, x3 = t_values
    y1, y2, y3 = y_values

    denominator = (x1 - x2) * (x1 - x3) * (x2 - x3)
    if abs(denominator) < _EPS:
        raise ZeroDivisionError("degenerated input points")

    c2 = (
        x3 * (y2 - y1)
        + x2 * (y1 - y3)
        + x1 * (y3 - y2)
    ) / denominator

    c1 = (
        x3**2 * (y1 - y2)
        + x2**2 * (y3 - y1)
        + x1**2 * (y2 - y3)
    ) / denominator

    c0 = (
        x2 * x3 * (x2 - x3) * y1
        + x3 * x1 * (x3 - x1) * y2
        + x1 * x2 * (x1 - x2) * y3
    ) / denominator

    return c2, c1, c0


def _has_three_samples(event: SampleEvent) -> bool:
    """
    Return True when t3/A3 are available.
    """
    return event.t3 is not None and event.a3 is not None


def _max_available_amplitude(event: SampleEvent) -> float:
    """
    Return the largest provided sparse amplitude.
    """
    values = [event.a1, event.a2]
    if event.a3 is not None:
        values.append(event.a3)
    return max(values)


def _error_result(event: SampleEvent, method: str, status: str) -> ReconstructionResult:
    """
    Build a result object for invalid input or invalid numerical operation.
    """
    return ReconstructionResult(
        event_id=event.event_id,
        method=method,
        t0_est=float("nan"),
        amax_est=float("nan"),
        status=status,
        true_t0=event.true_t0,
        true_amax=event.true_amax,
    )
