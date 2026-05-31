"""
PMT pulse model.

This module implements a compact Python version of the PMT pulse-shape model
described in the PMT modeling article:

- Gaussian component around the pulse peak.
- Exponential tail after the Gaussian-to-exponential matching point.
- Threshold-crossing times and time-over-threshold.

The implementation intentionally keeps the model simple enough to be useful as
a Python golden model for later FPGA-oriented work.
"""

from __future__ import annotations

from dataclasses import dataclass
import math


_EPS = 1e-12


@dataclass(frozen=True)
class PMTParameters:
    """
    Parameters of the compact PMT pulse model.

    sigma_ns:
        Gaussian width in ns.

    tau_ns:
        Exponential decay time in ns.

    threshold:
        Discriminator threshold.

    r_tilde:
        Normalization constant. In this simplified project model it is set to 1.
    """

    sigma_ns: float = 4.0
    tau_ns: float = 8.0
    threshold: float = 0.3
    r_tilde: float = 1.0


def match_time_offset(params: PMTParameters) -> float:
    """
    Return the Gaussian-to-exponential matching offset relative to pulse peak.

    x_match = sigma^2 / tau
    """
    return params.sigma_ns**2 / params.tau_ns


def match_normalization_c(params: PMTParameters) -> float:
    """
    Return C, the normalized pulse height at the matching point.

    C = exp(-0.5 * (sigma / tau)^2)
    """
    return math.exp(-0.5 * (params.sigma_ns / params.tau_ns) ** 2)


def pmt_voltage(
    t_ns: float,
    t_peak_ns: float,
    charge: float,
    params: PMTParameters,
) -> float:
    """
    Return PMT pulse voltage/amplitude at time t.

    x = t - t_peak

    Gaussian region:
        V = q * R_tilde * exp(-0.5 * (x / sigma)^2)

    Exponential tail:
        V = q * R_tilde / C * exp(-x / tau)
    """
    x = t_ns - t_peak_ns
    x_match = match_time_offset(params)

    if x <= x_match:
        return charge * params.r_tilde * math.exp(
            -0.5 * (x / params.sigma_ns) ** 2
        )

    c_value = match_normalization_c(params)
    return charge * params.r_tilde / c_value * math.exp(-x / params.tau_ns)


def threshold_crossings(
    t_peak_ns: float,
    charge: float,
    params: PMTParameters,
) -> tuple[float, float, float] | None:
    """
    Return leading edge, trailing edge and time-over-threshold.

    If the pulse does not exceed the threshold, return None.

    The formulas follow directly from the piecewise PMT model.

    Leading edge is always on the Gaussian rising part for q*R_tilde > V0:
        t_leading = t_peak - sigma * sqrt(2 * ln(q*R_tilde / V0))

    The trailing edge can be on the Gaussian falling part or on the exponential
    tail, depending on whether the matching-point amplitude is below threshold.
    """
    peak_amplitude = charge * params.r_tilde

    if peak_amplitude <= params.threshold:
        return None

    sigma = params.sigma_ns
    tau = params.tau_ns
    threshold = params.threshold
    c_value = match_normalization_c(params)

    log_ratio = math.log(peak_amplitude / threshold)
    x_leading = -sigma * math.sqrt(2.0 * log_ratio)

    v_match = peak_amplitude * c_value

    if v_match <= threshold:
        x_trailing = sigma * math.sqrt(2.0 * log_ratio)
    else:
        x_trailing = tau * math.log(peak_amplitude / (c_value * threshold))

    t_leading = t_peak_ns + x_leading
    t_trailing = t_peak_ns + x_trailing
    tot = t_trailing - t_leading

    return t_leading, t_trailing, tot


def sample_relative_to_peak(
    t_peak_ns: float,
    charge: float,
    params: PMTParameters,
    offset_ns: float,
) -> tuple[float, float]:
    """
    Return a sample placed at t_peak + offset_ns.
    """
    t_ns = t_peak_ns + offset_ns
    return t_ns, pmt_voltage(t_ns, t_peak_ns, charge, params)


def safe_positive(value: float, minimum: float = _EPS) -> float:
    """
    Prevent non-positive amplitudes after noise injection.
    """
    return max(value, minimum)
