# Leading Edge PMT Tester

Prosta aplikacja okienkowa do generowania impulsu PMT, rekonstrukcji zbocza z rzadkich próbek i eksportu CSV dla FPGA.

## Uruchomienie w Pythonie

```bash
pip install -r requirements.txt
python leading_edge_gui.py
```

## Budowanie pliku `.exe` na Windows

Kliknij dwukrotnie `build_exe.bat` albo uruchom:

```bat
build_exe.bat
```

Wynikowy plik będzie w:

```text
dist\LeadingEdgeTester.exe
```

## Format CSV

Przycisk **Zapisz CSV dla FPGA** zapisuje plik zgodny ze starym generatorem `example_samples.csv`.

Kolejność kolumn jest dokładnie taka sama:

```text
event_id,t1,A1,t2,A2,t3,A3,true_t0,true_amax,sigma_ns,tau_ns,threshold,charge,true_t_leading,true_t_trailing,true_tot
```

Znaczenie pól:

- `t1,A1,t2,A2,t3,A3` — trzy pary próbek dla modelu / FPGA,
- `true_t0` — referencyjny czas maksimum impulsu PMT,
- `true_amax` oraz `charge` — referencyjna amplituda impulsu,
- `sigma_ns`, `tau_ns`, `threshold` — parametry modelu PMT,
- `true_t_leading`, `true_t_trailing`, `true_tot` — referencyjne wartości progu i time-over-threshold.

Jeżeli w GUI wybrano więcej niż 3 próbki, eksport legacy zapisuje trzy reprezentatywne próbki: pierwszą, środkową i ostatnią. Jeżeli wybrano 2 próbki, kolumny `t3,A3` są uzupełniane zerami, żeby zachować zgodność nagłówka CSV.
