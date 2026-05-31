"""
Data models used by the leading edge reconstruction reference model.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class SampleEvent:
    """
    Single sparse PMT event.

    The reconstruction algorithms receive two or three samples.
    t1/A1 and t2/A2 are mandatory.
    t3/A3 is optional but recommended for exponential and logarithmic modes.

    true_t0:
        Reference PMT peak time.

    true_amax:
        Reference PMT peak amplitude.

    sigma_ns, tau_ns, threshold:
        PMT model parameters used for reference-curve plotting.

    true_t_leading, true_t_trailing, true_tot:
        Reference threshold-crossing data from the PMT model.
    """

    event_id: int
    t1: float
    a1: float
    t2: float
    a2: float
    t3: float | None = None
    a3: float | None = None
    true_t0: float | None = None
    true_amax: float | None = None
    sigma_ns: float | None = None
    tau_ns: float | None = None
    threshold: float | None = None
    charge: float | None = None
    true_t_leading: float | None = None
    true_t_trailing: float | None = None
    true_tot: float | None = None


@dataclass(frozen=True)
class ReconstructionResult:
    """
    Output returned by a single reconstruction method.
    """

    event_id: int
    method: str
    t0_est: float
    amax_est: float
    status: str
    true_t0: float | None = None
    true_amax: float | None = None

    @property
    def t0_error(self) -> float | None:
        """Return t0 estimation error if a reference value is available."""
        if self.true_t0 is None:
            return None
        return self.t0_est - self.true_t0

    @property
    def amax_error(self) -> float | None:
        """Return amplitude estimation error if a reference value is available."""
        if self.true_amax is None:
            return None
        return self.amax_est - self.true_amax
