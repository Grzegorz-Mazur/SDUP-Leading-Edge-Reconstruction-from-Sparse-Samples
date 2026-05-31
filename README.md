# Leading Edge Reconstruction from Sparse PMT Samples

Python reference model for a university FPGA project:

**Leading Edge Reconstruction from Sparse Samples**  
Target platform: **AMD/Xilinx Zynq UltraScale+ MPSoC ZCU106**  
Software environment: **Python / PYNQ / Vivado-oriented verification flow**

The project compares three sparse-sample reconstruction methods:

- **Linear interpolation**
- **Exponential interpolation**
- **Logarithmic / Gaussian-domain interpolation**

The Python model is intended to be used as a **golden reference** before implementing the selected algorithm in RTL and integrating it with AXI-Lite / AXI-Stream interfaces.

---

## 1. Project Structure

```text
leading_edge_python_model_v2/
├── main.py
├── requirements.txt
├── README.md
├── data/
│   └── example_samples.csv
├── tools/
│   └── generate_list_from_pmt.py
├── docs/
│   └── plots/
│       ├── sparse_samples_and_reconstructed_timing.png
│       ├── t0_estimation_comparison.png
│       ├── t0_reconstruction_RMSE_by_method.png
│       ├── reference_PMT_time_over_threshold.png
└── src/
    └── leading_edge/
        ├── __init__.py
        ├── data.py
        ├── interpolation.py
        ├── metrics.py
        ├── models.py
        ├── plotting.py
        └── pmt_model.py
```

---

## 2. Installation

Create and activate a virtual environment:

```bash
python3 -m venv venv
source venv/bin/activate
```

Install required packages:

```bash
pip install -r requirements.txt
```

Required Python libraries:

```text
numpy
pandas
matplotlib
```

---

## 3. Quick Start

Run the PMT synthetic source:

```bash
python main.py --source pmt
```

Run deterministic hardcoded list vectors:

```bash
python main.py --source list
```

Run CSV input:

```bash
python main.py --source csv --csv data/example_samples.csv
```

The program prints a result table and opens all plots at once.

---

## 4. PMT Model

The synthetic generator follows the PMT pulse-shape idea used in the PMT modeling article:

- Gaussian pulse component before the matching point,
- exponential tail after the matching point,
- discriminator threshold,
- leading-edge and trailing-edge timestamp estimation,
- time-over-threshold calculation.

The implemented reference pulse is:

```text
x = t - t_peak

V(t, q) = q * R_tilde * exp(-0.5 * (x / sigma)^2),     x <= x_match
V(t, q) = q * R_tilde / C * exp(-x / tau),              x >  x_match

x_match = sigma^2 / tau
C       = exp(-0.5 * (sigma / tau)^2)
```

This keeps the Gaussian section and the exponential tail continuous in value and derivative at the matching point.

The default model parameters are intentionally simple and FPGA-friendly:

```text
sigma = 4.0 ns
tau = 8.0 ns
threshold = 0.3
R_tilde = 1.0
```

---

## 5. Random and Reproducible PMT Events

By default, PMT events are random:

```bash
python main.py --source pmt
```

The program prints the internally selected seed:

```text
Random PMT seed selected: 123456789
```

You can reuse that seed later to reproduce exactly the same event set.

To force a fixed seed:

```bash
python main.py --source pmt --seed 7
```

To generate more events:

```bash
python main.py --source pmt --events 50
```

To add more amplitude noise:

```bash
python main.py --source pmt --noise 0.05
```

Recommended workflow:

```bash
python main.py --source pmt --events 20 --seed 7 --noise 0.02
```

Use fixed seeds for Python-vs-FPGA comparisons and RTL testbench generation.

---

## 6. Generating CSV from the PMT Model

Generate a CSV file using a random PMT seed:

```bash
python main.py --source pmt --save-example-csv --csv data/example_samples.csv
```

Generate a reproducible CSV file:

```bash
python main.py --source pmt --save-example-csv --csv data/example_samples.csv --seed 7
```

Generate a larger CSV file:

```bash
python main.py --source pmt --save-example-csv --csv data/example_samples.csv --events 100 --seed 7
```

The CSV format is:

```text
event_id,t1,A1,t2,A2,t3,A3,true_t0,true_amax,sigma_ns,tau_ns,threshold,charge,true_t_leading,true_t_trailing,true_tot
```

Required columns for external data:

```text
event_id,t1,A1,t2,A2
```

Recommended columns:

```text
t3,A3,true_t0,true_amax,sigma_ns,tau_ns,threshold
```

When `sigma_ns`, `tau_ns`, and `threshold` are available, the plotted PMT reference curve is physically consistent with the input samples.

---

## 7. Generating Python List Vectors from the PMT Model

The project also contains a helper script:

```text
tools/generate_list_from_pmt.py
```

Run it with a fixed seed:

```bash
python tools/generate_list_from_pmt.py --events 5 --seed 7 --noise 0.0
```

Run it with a random seed:

```bash
python tools/generate_list_from_pmt.py --events 5
```

The script prints a ready-to-paste Python list:

```python
return [
    SampleEvent(...),
    SampleEvent(...),
]
```

Paste the printed output into the function:

```python
def get_list_events() -> list[SampleEvent]:
```

located in:

```text
src/leading_edge/data.py
```

This is useful when you want hardcoded, deterministic test vectors that can later be copied into an RTL testbench.

---

## 8. Reconstruction Methods

### Linear

The linear method uses two samples and extrapolates a simple straight-line model:

```text
t_cross = t1 - A1 * (t2 - t1) / (A2 - A1)
```

This is the cheapest method for FPGA implementation. It is useful as a baseline.

### Exponential

The exponential method uses three samples and estimates an exponential slope in the log-amplitude domain:

```text
tau_est = (t3 - t2) / ln(A3 / A2)
t_cross = t1 - tau_est * ln(A1 / threshold)
```

This method is included as an FPGA-relevant comparison because it requires a logarithm or LUT approximation.

### Logarithmic / Gaussian-Domain

The logarithmic method uses three samples and fits:

```text
ln(A) = c2*t^2 + c1*t + c0
```

For a Gaussian rising edge, this is a physically meaningful transformation. The pulse peak estimate is the vertex of the fitted parabola:

```text
t0 = -c1 / (2*c2)
```

The amplitude estimate is:

```text
Amax = exp(ln(A(t0)))
```

This is the most consistent method for the Gaussian leading edge.

---

## 9. Plotting

The program opens all plots simultaneously:

1. Sparse samples and reconstructed `t0` for selected events.
2. Method comparison over all events.
3. RMSE comparison.
4. Time-over-threshold comparison when reference PMT values are available.

The first event plots use explicit colors for reconstructed markers:

```text
linear       -> red
exponential  -> green
logarithmic  -> purple
```

### Sparse samples and reconstructed t0 for selected events
<img src="leading_edge_python_model_v2/docs/plots/sparse_samples_and_reconstructed_timing.png" width="700">

This plot presents selected PMT events together with their sparse input samples and reconstructed timing points.

The sparse samples represent the limited set of amplitude measurements available on the rising edge of the PMT pulse. These are the input data used by the reconstruction algorithms. For each selected event, the plot shows where the individual methods estimate the pulse timing t0.

The purpose of this plot is to provide a direct visual check of the reconstruction process. It allows verifying whether the estimated t0 values are placed in physically reasonable positions with respect to the sampled rising edge. Large deviations between the reconstructed markers and the expected pulse position may indicate that a given method is not well suited for that event or that the input samples are insufficient.


### Method comparison over all events
<img src="leading_edge_python_model_v2/docs/plots/t0_estimation_comparison.png" width="700">

This plot compares the estimated t0 values obtained by different reconstruction methods over the complete set of generated or loaded events.

The reference value represents the expected timing obtained from the PMT model or from the input dataset. The reconstructed values are the results produced by the implemented interpolation methods.

The plot is used to evaluate whether the reconstruction methods follow the reference timing consistently. If a method is accurate, its estimated values should stay close to the reference values over the full event range. Visible offsets, spreading, or outliers indicate reconstruction error.

This comparison is important because it shows not only the behavior of the algorithms on individual examples, but also their stability over a larger dataset. It is therefore a useful step before selecting the method that should later be mapped to the FPGA implementation.


### RMSE comparison
<img src="leading_edge_python_model_v2/docs/plots/t0_reconstruction_RMSE_by_method.png" width="700">

This plot presents the RMSE value for each reconstruction method.

RMSE stands for Root Mean Square Error and is calculated as:

```text
RMSE = sqrt(mean((t0_estimated - t0_reference)^2))
```

The RMSE value describes the average reconstruction error of a method, with larger errors penalized more strongly because the error is squared before averaging.

A lower RMSE means that the method reconstructs t0 more accurately. A higher RMSE means that the estimated timing differs more strongly from the reference value.

This plot provides a compact quantitative comparison between the implemented methods. It is especially useful for deciding which algorithm gives the best trade-off between accuracy and expected hardware complexity.


### Time-over-threshold comparison
<img src="leading_edge_python_model_v2/docs/plots/reference_PMT_time_over_threshold.png" width="700">

This plot shows the reference PMT time-over-threshold behavior when reference PMT values are available.

Time-over-threshold describes the time interval during which the PMT pulse remains above the discriminator threshold. In the context of this project, it is related to the pulse amplitude and to the leading/trailing edge timing of the signal.

The purpose of this plot is to compare the generated or reconstructed timing behavior with the reference PMT model. It helps verify whether the implemented model produces physically meaningful timing values and whether the generated samples are consistent with the expected PMT pulse behavior.

This plot is mainly used as a model validation step. Before moving the algorithm to the FPGA implementation, the Python model should first produce results that agree with the assumed PMT reference behavior.

---

## 10. Typical Development Flow

Recommended project workflow:

1. Generate PMT events in Python.
2. Run all interpolation methods.
3. Compare reconstruction error and RMSE.
4. Export CSV or hardcoded list vectors.
5. Use the same vectors in RTL testbench.
6. Compare Python golden model with FPGA output.
7. Measure performance for ARM / AXI-Lite sequential / AXI-Stream pipelined versions.

---

## 11. Notes

This model is not a complete detector simulation. It intentionally focuses on the pulse-shape and sparse-sample reconstruction problem needed for FPGA implementation.

Not included in this version:

- full PMT charge distribution,
- underamplification model,
- thresholdband model,
- saturation at very high charge,
- full statistical time-over-threshold distribution fitting.

