# Leading Edge Reconstruction

Project for sparse-sample PMT timing reconstruction and FPGA-oriented
implementation on AMD/Xilinx Zynq UltraScale+ MPSoC.

Target board: **ZCU106**  
Vivado version used: **2022.1**  
Main FPGA integration project: **Vivado/Leading_edge_AXI**  
Current hardware interface: **AXI4-Lite register interface**  
AXI-Stream status: **not implemented in the current architecture**

The project compares three reconstruction methods:

- **LIN** - linear interpolation / extrapolation,
- **EXP** - exponential-domain threshold reconstruction,
- **LOG** - logarithmic / Gaussian-domain peak reconstruction.

The Python part is used as a reference model and data generator. The Vivado part
contains the RTL core, testbenches, packaged AXI-Lite IP and the current Block
Design used for system integration.

---

## 1. Repository Layout

```text
SDUP/
|-- README.md
|-- leading_edge_axi_lite_pynq.ipynb
|-- leading_edge_axi_lite_offline_report.ipynb
|-- leading_edge_offline_results.csv
|-- leading_edge_python_model_v2/
|   |-- main.py
|   |-- requirements.txt
|   |-- data/
|   |   `-- example_samples.csv
|   |-- src/
|   |   `-- leading_edge/
|   |       |-- data.py
|   |       |-- interpolation.py
|   |       |-- metrics.py
|   |       |-- models.py
|   |       |-- plotting.py
|   |       `-- pmt_model.py
|   `-- tools/
|       `-- generate_list_from_pmt.py
|-- leading_edge_tester_app/
|-- leading_edge_viewer_app/
`-- Vivado/
    |-- Leading_edge_core_TB/
    |-- Leading_edge_AXI/
    `-- Vivado_old/
```

`Vivado_old/` is kept only as an archive of older work. The active Vivado flow is
split into two projects:

```text
Vivado/Leading_edge_core_TB  - RTL, testbenches and packaged custom IP
Vivado/Leading_edge_AXI      - ZCU106 system integration Block Design
```

---

## 2. Python Reference Model

Main folder:

```text
leading_edge_python_model_v2/
```

Run the PMT model:

```bash
cd leading_edge_python_model_v2
python main.py --source pmt --events 20 --seed 7
```

Run from CSV:

```bash
python main.py --source csv --csv data/example_samples.csv
```

Generate a reproducible CSV:

```bash
python main.py --source pmt --save-example-csv --csv data/example_samples.csv --events 20 --seed 7
```

CSV format used by the model and RTL-oriented tests:

```text
event_id,t1,A1,t2,A2,t3,A3,true_t0,true_amax,sigma_ns,tau_ns,threshold,charge,true_t_leading,true_t_trailing,true_tot
```

The sparse RTL input is not a dense waveform. Each event contains only three
selected samples from the leading edge:

```text
(t1, A1), (t2, A2), (t3, A3)
```

---

## 3. Reconstruction Methods

### LIN

Linear method using the first two samples:

```text
t0 = t1 - A1 * (t2 - t1) / (A2 - A1)
```

In the current RTL this is an extrapolation to the zero level. It is simple and
cheap in hardware, but it must be interpreted differently than a threshold
crossing.

### EXP

Exponential-domain threshold method:

```text
tau = (t3 - t2) / (ln(A3) - ln(A2))
t0  = t1 - tau * (ln(A1) - ln(threshold))
```

This method estimates the time at which the signal crosses the configured
threshold.

### LOG

Gaussian-domain method using a quadratic fit in the logarithmic amplitude
domain:

```text
ln(A(t)) = c2*t^2 + c1*t + c0
t0       = -c1 / (2*c2)
```

This method estimates the peak time of a Gaussian-like pulse and is compared
against `true_t0` in the offline report.

---

## 4. RTL Project: Leading_edge_core_TB

Main Vivado project:

```text
Vivado/Leading_edge_core_TB/Leading_edge_core_TB.xpr
```

Important source files:

```text
Vivado/Leading_edge_core_TB/Leading_edge_core_TB.srcs/sources_1/new/
|-- leading_edge_math.vh
|-- leading_edge_method_linear.v
|-- leading_edge_method_exp.v
|-- leading_edge_method_log.v
|-- leading_edge_core.v
|-- leading_edge_axi_lite_regs.v
`-- leading_edge_ip_lite.v
```

Testbenches:

```text
Vivado/Leading_edge_core_TB/Leading_edge_core_TB.srcs/sim_1/new/
|-- tb_leading_edge_core_unit.v
|-- tb_leading_edge_core_csv.v
`-- tb_leading_edge_ip_lite.v
```

Packaged IP repository:

```text
Vivado/Leading_edge_core_TB/ip_repo/leading_edge_ip_lite/
```

This packaged IP is used by the integration project `Leading_edge_AXI`.

Current RTL verification status:

```text
tb_leading_edge_core_unit complete: 19 PASS, 0 FAIL
```

---

## 5. AXI-Lite Register Map

The active software interface is AXI4-Lite. All numeric data registers use
signed **Q16.16** fixed-point format:

```text
q16_value = real_value * 65536
```

Register map:

| Offset | Register | Access | Description |
|---:|---|---|---|
| `0x00` | `CONTROL` | RW / pulse | bit 0 `start`, bits 2:1 `mode_sel`, bit 8 `clear_done` |
| `0x04` | `STATUS` | RO | bit 0 `busy`, bit 1 `done`, bit 2 `overflow`, bit 3 `core_valid` |
| `0x08` | `THRESHOLD` | RW | signed Q16.16 threshold |
| `0x0C` | `T1` | RW | signed Q16.16 time sample 1 |
| `0x10` | `A1` | RW | signed Q16.16 amplitude sample 1 |
| `0x14` | `T2` | RW | signed Q16.16 time sample 2 |
| `0x18` | `A2` | RW | signed Q16.16 amplitude sample 2 |
| `0x1C` | `T3` | RW | signed Q16.16 time sample 3 |
| `0x20` | `A3` | RW | signed Q16.16 amplitude sample 3 |
| `0x24` | `T0_EST` | RO | signed Q16.16 reconstructed time |
| `0x28` | `AMAX_EST` | RO | signed Q16.16 reconstructed amplitude |
| `0x2C` | `VERSION` | RO | current value `0x00010000` |

Mode selection:

```text
0 - LIN
1 - EXP
2 - LOG
```

Typical AXI-Lite sequence:

1. Write `THRESHOLD`.
2. Write `T1/A1/T2/A2/T3/A3`.
3. Write `CONTROL` with mode and `start=1`.
4. Poll `STATUS.done`.
5. Read `T0_EST`, `AMAX_EST` and `STATUS`.
6. Clear sticky done with `CONTROL[8]` or start the next event.

---

## 6. Vivado Integration Project: Leading_edge_AXI

Main project:

```text
Vivado/Leading_edge_AXI/Leading_edge_AXI.xpr
```

Part and board:

```text
part       = xczu7ev-ffvc1156-2-e
board_part = xilinx.com:zcu106:part0:2.6
```

IP repository used by the project:

```text
Vivado/Leading_edge_core_TB/ip_repo
```

The current main Block Design is:

```text
Vivado/Leading_edge_AXI/Leading_edge_AXI.srcs/sources_1/bd/leading_edge_axi_lite_bd/leading_edge_axi_lite_bd.bd
```

Current top wrapper:

```text
leading_edge_axi_lite_bd_wrapper
```

Current architecture:

```text
Zynq UltraScale+ Processing System
    M_AXI_HPM0_FPD
        |
        v
AXI SmartConnect
        |
        v
leading_edge_ip_lite_0 / s_axi
```

Clock and reset:

```text
processing_system/pl_clk0       -> AXI SmartConnect, leading_edge_ip_lite_0
processing_system/pl_resetn0    -> proc_sys_reset
proc_sys_reset/peripheral_aresetn -> AXI and custom IP reset
```

Address map:

```text
leading_edge_ip_lite_0: 0xA0000000, range 4K
```

The older Block Design:

```text
leading_edge_axi_bd
```

is still present as a previous/reference design. The active, cleaner design for
the current AXI-Lite architecture is `leading_edge_axi_lite_bd`.

---

## 7. Notebook Files

Top-level notebooks:

```text
leading_edge_axi_lite_pynq.ipynb
leading_edge_axi_lite_offline_report.ipynb
```

The same notebooks are also copied into:

```text
Vivado/Leading_edge_AXI/
```

Use `leading_edge_axi_lite_pynq.ipynb` only when the PYNQ/ZCU106 board is
available and responsive. It loads the XSA, finds the AXI-Lite IP and runs
register-level tests.

Use `leading_edge_axi_lite_offline_report.ipynb` for a board-independent report.
It contains reference calculations, tables and plots based on
`example_samples.csv` and `leading_edge_offline_results.csv`.

Current PYNQ status:

```text
The PYNQ notebook is prepared, but hardware execution should be treated as a
separate validation step. If loading the XSA breaks communication with the
board, do not treat that run as a valid FPGA measurement.
```

---

## 8. Git / Vivado Hygiene

Keep source files and readable project metadata in Git:

```text
README.md
leading_edge_python_model_v2/
leading_edge_axi_lite_*.ipynb
leading_edge_offline_results.csv
Vivado/Leading_edge_core_TB/Leading_edge_core_TB.xpr
Vivado/Leading_edge_core_TB/Leading_edge_core_TB.srcs/
Vivado/Leading_edge_core_TB/ip_repo/leading_edge_ip_lite/
Vivado/Leading_edge_AXI/Leading_edge_AXI.xpr
Vivado/Leading_edge_AXI/Leading_edge_AXI.srcs/sources_1/bd/
```

Do not commit generated Vivado products:

```text
.Xil/
*.cache/
*.gen/
*.hw/
*.runs/
*.sim/
*.ip_user_files/
*.bit
*.hwh
*.xsa
*.dcp
*.rpt
*.jou
*.log
```

The exported `.xsa` is useful for PYNQ, but it is a generated hardware handoff
artifact. Keep it locally unless the repository policy explicitly requires
checking exported hardware files into Git.

---

## 9. Suggested Development Flow

1. Generate or load PMT sparse samples in Python.
2. Run the Python reference model and inspect errors.
3. Use the same vectors in RTL simulation.
4. Verify `leading_edge_core` and `leading_edge_ip_lite` in
   `Leading_edge_core_TB`.
5. Package/update `leading_edge_ip_lite` in the local IP repo.
6. Open `Leading_edge_AXI` and refresh the IP catalog.
7. Validate `leading_edge_axi_lite_bd`.
8. Generate bitstream and export XSA only when hardware testing is needed.
9. Use the PYNQ notebook for board-level AXI-Lite tests.

---

## 10. Current Status

- Python reference model: available.
- Sparse PMT CSV input: available.
- RTL core: implemented.
- LIN/EXP/LOG method modules: separated.
- AXI4-Lite wrapper: implemented.
- AXI4-Stream wrapper: not part of the current architecture.
- Packaged custom IP: available in `ip_repo/leading_edge_ip_lite`.
- Vivado Block Design: `leading_edge_axi_lite_bd`.
- PYNQ notebook: prepared, requires stable board connection for validation.
