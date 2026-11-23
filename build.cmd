@echo off
rem Buduje riverraid.cas: xex_info.inc -> loader (MADS) -> plik CAS.
rem Logo przerabia osobno: python gen_gfx.py bekapeka_logo.png gfx_data.inc (wymaga Pillow)
setlocal
cd /d "%~dp0"
python xex_info.py RiverRaid.xex xex_info.inc || exit /b 1
mads.exe riverraid_tape.asm -o:riverraid_tape.bin -l -t || exit /b 1
python build_cas.py riverraid_tape.bin RiverRaid.xex riverraid.cas || exit /b 1
