"""
Plotting utilities.

The plots are intentionally kept separate from the algorithm modules so the
interpolation logic remains clean and easier to port to hardware-oriented code.
"""

from __future__ import annotations

import math

import matplotlib.pyplot as plt

from .metrics import rmse_by_method
from .models import ReconstructionResult, SampleEvent
from .pmt_model import PMTParameters, pmt_voltage


METHOD_COLORS = {
    "linear": "tab:orange",
    "exponential": "tab:green",
    "logarithmic": "tab:purple",
}


REFERENCE_COLORS = {
    "threshold": "black",
    "true_leading": "tab:cyan",
    "true_trailing": "tab:brown",
    "true_peak": "tab:red",
}

def create_reconstructed_signal_plots(
    events: list[SampleEvent],
    results: list[ReconstructionResult],
    max_events: int = 3,
) -> None:
    """
    Create reconstructed-signal plots for selected events.

    The figures are created without calling plt.show(), so all windows can be
    displayed simultaneously by the main script.
    """
    selected_events = events[:max_events]

    for event in selected_events:
        event_results = [result for result in results if result.event_id == event.event_id]

        plt.figure()
        plt.title(f"Event {event.event_id}: sparse samples and reconstructed timing")
        plt.xlabel("time [ns]")
        plt.ylabel("amplitude")

        if _can_draw_reference_curve(event):
            params = PMTParameters(
                sigma_ns=event.sigma_ns,
                tau_ns=event.tau_ns,
                threshold=event.threshold,
                r_tilde=1.0,
            )

            t_min = min(event.t1, event.t2, event.t3 or event.t2)
            if event.true_t_leading is not None:
                t_min = min(t_min, event.true_t_leading)
            t_min -= 2.0

            t_max = event.true_t0 + 4.0 * event.tau_ns
            if event.true_t_trailing is not None:
                t_max = max(t_max, event.true_t_trailing + 2.0)

            t_axis = [t_min + i * (t_max - t_min) / 700 for i in range(701)]
            y_axis = [
                pmt_voltage(t, event.true_t0, event.charge, params)
                for t in t_axis
            ]
            plt.plot(t_axis, y_axis, label="reference PMT pulse")

            if event.threshold is not None:
                plt.axhline(
                    event.threshold,
                    color=REFERENCE_COLORS["threshold"],
                    linestyle="--",
                    linewidth=1.4,
                    label="threshold",
                )

            if event.true_t_leading is not None:
                plt.axvline(
                    event.true_t_leading,
                    color=REFERENCE_COLORS["true_leading"],
                    linestyle="-",
                    linewidth=1.4,
                    label="true leading edge",
                )

            if event.true_t_trailing is not None:
                plt.axvline(
                    event.true_t_trailing,
                    color=REFERENCE_COLORS["true_trailing"],
                    linestyle="-",
                    linewidth=1.4,
                    label="true trailing edge",
                )

        sample_times = [event.t1, event.t2]
        sample_amps = [event.a1, event.a2]

        if event.t3 is not None and event.a3 is not None:
            sample_times.append(event.t3)
            sample_amps.append(event.a3)

        plt.scatter(
            sample_times,
            sample_amps,
            marker="o",
            s=55,
            label="sparse samples",
        )

        if event.true_t0 is not None:
            plt.axvline(
                event.true_t0,
                color=REFERENCE_COLORS["true_peak"],
                linestyle="-.",
                linewidth=1.6,
                label="true peak t0",
            )

        for result in event_results:
            if result.status == "valid" and not math.isnan(result.t0_est):
                plt.axvline(
                    result.t0_est,
                    linestyle=":",
                    linewidth=2.0,
                    color=METHOD_COLORS.get(result.method, None),
                    label=f"{result.method} t0",
                )

        plt.grid(True)
        plt.legend()
        plt.tight_layout()


def create_method_comparison_plot(results: list[ReconstructionResult]) -> None:
    """
    Compare t0 estimates from all methods in one figure.
    """
    plt.figure()
    plt.title("t0 estimation comparison")
    plt.xlabel("event ID")
    plt.ylabel("t0 estimate [ns]")

    methods = sorted({result.method for result in results})

    for method in methods:
        method_results = [
            result
            for result in results
            if result.method == method and result.status == "valid"
        ]
        x_values = [result.event_id for result in method_results]
        y_values = [result.t0_est for result in method_results]
        plt.plot(
            x_values,
            y_values,
            marker="o",
            color=METHOD_COLORS.get(method, None),
            label=method,
        )

    reference_results = [
        result
        for result in results
        if result.true_t0 is not None and result.method == methods[0]
    ]

    if reference_results:
        x_ref = [result.event_id for result in reference_results]
        y_ref = [result.true_t0 for result in reference_results]
        plt.plot(x_ref, y_ref, marker="x", linestyle="--", label="true t0")

    plt.grid(True)
    plt.legend()
    plt.tight_layout()


def create_error_summary_plot(results: list[ReconstructionResult]) -> None:
    """
    Show RMSE comparison for all reconstruction methods.
    """
    rmse_values = rmse_by_method(results)

    plt.figure()
    plt.title("t0 reconstruction RMSE by method")
    plt.xlabel("method")
    plt.ylabel("RMSE [ns]")

    methods = list(rmse_values.keys())
    values = [rmse_values[method] for method in methods]
    colors = [METHOD_COLORS.get(method, None) for method in methods]

    plt.bar(methods, values, color=colors)
    plt.grid(True, axis="y")
    plt.tight_layout()


def create_tot_comparison_plot(events: list[SampleEvent]) -> None:
    """
    Plot reference time-over-threshold for events that contain PMT metadata.
    """
    events_with_tot = [
        event
        for event in events
        if event.true_tot is not None and event.charge is not None
    ]

    if not events_with_tot:
        return

    plt.figure()
    plt.title("Reference PMT time-over-threshold")
    plt.xlabel("charge / peak amplitude")
    plt.ylabel("time-over-threshold [ns]")

    x_values = [event.charge for event in events_with_tot]
    y_values = [event.true_tot for event in events_with_tot]

    plt.scatter(x_values, y_values, marker="o", label="generated PMT events")
    plt.grid(True)
    plt.legend()
    plt.tight_layout()


def _can_draw_reference_curve(event: SampleEvent) -> bool:
    """
    Return True when enough PMT metadata is available for reference plotting.
    """
    return (
        event.true_t0 is not None
        and event.charge is not None
        and event.sigma_ns is not None
        and event.tau_ns is not None
        and event.threshold is not None
    )
