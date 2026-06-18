# Leading Edge Viewer

Druga aplikacja okienkowa do projektu **Leading Edge Reconstruction**. Służy do porównywania:

1. pliku CSV wygenerowanego przez `leading_edge_gui`, np. `fpga_input_seed_1234_0.csv`,
2. pliku wynikowego z testbencha Vivado, np. `fpga_input_seed_1234_0_results.csv`.

Aplikacja pokazuje rzeczywisty impuls PMT, próbki wejściowe, rekonstrukcję referencyjną oraz wynik RTL z testbencha. Oblicza różnice czasowe pomiędzy `expected_t0`, `t0_est` i `true_t0`.

## Obsługiwane formaty CSV

### Input CSV z `leading_edge_gui`

Wymagany nagłówek:

```csv
event_id,t1,A1,t2,A2,t3,A3,true_t0,true_amax,sigma_ns,tau_ns,threshold,charge,true_t_leading,true_t_trailing,true_tot
```

### Results CSV z testbencha Vivado

Wymagany nagłówek:

```csv
event_id,method_id,t1,A1,t2,A2,t3,A3,threshold,true_t0,expected_t0,t0_est,amax_est,error_vs_expected_ns,error_vs_true_ns,start_cycle,valid_cycle,latency_cycles,t0_raw,amax_raw,pass
```

`method_id` oznacza:

- `0` — linear,
- `1` — exponential,
- `2` — logarithmic / Gauss.

## Uruchamianie z Pythona

```bat
python leading_edge_viewer.py
```

## Budowanie EXE na Windowsie

Uruchom:

```bat
build_exe.bat
```

Po zakończeniu kompilacji plik powinien pojawić się tutaj:

```text
dist\LeadingEdgeViewer.exe
```

## Uwaga o wykresie RTL

Plik `*_results.csv` przechowuje wynik skalarny `t0_est` i `amax_est`, a nie pełne współczynniki krzywej RTL. Dlatego wykres RTL w viewerze jest wizualizacją: aplikacja bierze krzywą referencyjną z próbek wejściowych, przesuwa ją o `t0_est - expected_t0` i skaluje amplitudowo do `amax_est`. Liczby w panelu porównania są liczone bezpośrednio z wartości CSV.
