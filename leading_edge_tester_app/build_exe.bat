@echo off
setlocal
cd /d %~dp0

if not exist .venv (
    py -m venv .venv
)

call .venv\Scripts\activate.bat
python -m pip install --upgrade pip
pip install -r requirements.txt pyinstaller
pyinstaller --noconsole --onefile --name LeadingEdgeTester leading_edge_gui.py

echo.
echo Gotowy plik powinien znajdowac sie w katalogu dist\LeadingEdgeTester.exe
pause
