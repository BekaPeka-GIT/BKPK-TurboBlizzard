@echo off
rem Buduje ninja.cas: ninja_info.inc -> loader (MADS) -> plik CAS.
rem Logo (gfx_data.inc) jest wspolne z River Raid: python gen_gfx.py bekapeka_logo.png gfx_data.inc (wymaga Pillow)
setlocal
cd /d "%~dp0"
python xex_info.py Ninja.xex ninja_info.inc || exit /b 1
mads.exe ninja_tape.asm -o:ninja_tape.bin -l -t || exit /b 1
python build_cas.py ninja_tape.bin Ninja.xex ninja.cas --desc "Ninja" || exit /b 1
