@echo off
setlocal
cd /d "%~dp0"
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
python -m PyInstaller --noconsole --onefile --name LeadingEdgeViewer leading_edge_viewer.py
echo.
echo Gotowe. Plik EXE powinien znajdowac sie w: dist\LeadingEdgeViewer.exe
pause
