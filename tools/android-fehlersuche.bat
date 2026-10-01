@echo off
REM ===========================================================================
REM  Android-Fehlersuche fuer den Startabbruch - NUR DOPPELKLICKEN.
REM
REM  Dieses Skript macht alles selbst:
REM    1. sucht adb
REM    2. loescht den alten Logcat
REM    3. startet die App
REM    4. wartet 12 Sekunden
REM    5. schreibt den Log als Textdatei neben diese Datei
REM
REM  Danach: die erzeugte Datei "android-log.txt" oeffnen und den Inhalt
REM  weitergeben. Mehr ist nicht noetig - auch nicht, wenn Android fragt,
REM  ob das USB-Debugging erlaubt werden soll (ja erlauben).
REM ===========================================================================

setlocal
cd /d "%~dp0"

echo.
echo  ==========================================================
echo   Thestia - Android-Fehlersuche
echo  ==========================================================
echo.

REM --- adb finden -------------------------------------------------------------
set "ADB="
where adb >nul 2>&1 && set "ADB=adb"

if not defined ADB (
  if exist "%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" (
    set "ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"
  )
)
if not defined ADB (
  if exist "%ProgramFiles%\Android\Android Studio\platform-tools\adb.exe" (
    set "ADB=%ProgramFiles%\Android\Android Studio\platform-tools\adb.exe"
  )
)

if not defined ADB (
  echo  FEHLER: adb wurde nicht gefunden.
  echo.
  echo  Loesung: Android Studio installieren, oder den Platform-Tools-
  echo  Ordner aus dem Android-SDK herunterladen:
  echo    https://developer.android.com/tools/releases/platform-tools
  echo  Danach PATH erweitern oder den Ordner nach C:\android-tools legen
  echo  und den Ordner hierher kopieren.
  echo.
  pause
  exit /b 1
)

echo  adb gefunden: %ADB%
echo.

REM --- Geraet pruefen ---------------------------------------------------------
"%ADB%" start-server >nul 2>&1
"%ADB%" devices > "%TEMP%\th_devices.txt" 2>&1

findstr /C:"device" "%TEMP%\th_devices.txt" | findstr /V "list devices" | findstr /V "unauthorized" | findstr /V "offline" >nul 2>&1
if errorlevel 1 (
  echo  FEHLER: Kein nutzbares Geraet per USB verbunden.
  echo.
  echo  Bitte am Telefon:
  echo    Einstellungen, dann "Ueber das Telefon", dann
  echo    "Build-Nummer" siebenmal antippen.
  echo    Danach: Einstellungen, Entwickleroptionen,
  echo    USB-Debugging einschalten.
  echo    Beim Anschliessen am Bildschirm bestaetigen.
  echo.
  echo  Erkannte Geraete:
  type "%TEMP%\th_devices.txt%"
  echo.
  echo  Steht dort ein Geraet mit "offline", ist es ein Emulator oder
  echo  das Kabel haengt. Kabel abziehen und neu verbinden.
  echo.
  pause
  exit /b 1
)

echo  Geraet verbunden.
echo.

REM --- Log leeren und App starten --------------------------------------------
echo  Altes Log wird geloescht...
"%ADB%" logcat -c >nul 2>&1
"%ADB%" shell am force-stop com.thestia.app >nul 2>&1

echo.
echo  ==================================================================
echo   JETZT: App am Telefon von Hand oeffnen.
echo   Warte, bis der Fehler erscheint (dauert wenige Sekunden).
echo   Dieser Bildschirm zaehlt 15 Sekunden von selbst.
echo  ==================================================================
echo.

"%ADB%" shell monkey -p com.thestia.app -c android.intent.category.LAUNCHER 1 >nul 2>&1

set /a cnt=15
:waitloop
if %cnt%==0 goto done
timeout /t 1 /nobreak >nul
set /a cnt-=1
goto waitloop
:done

REM --- Log schreiben ----------------------------------------------------------
echo  Log wird geschrieben...
"%ADB%" logcat -d -v threadtime > "android-log.txt" 2>&1

REM Nur die relevanten Zeilen in eine zweite, lesbare Datei. Die
REM vollstaendige Datei bleibt daneben, falls doch etwas anderes
ROM-spezifisch ist.
"%ADB%" logcat -d -v threadtime 2>&1 | findstr /I /C:"AndroidRuntime" /C:"FATAL" /C:"com.thestia.app" /C:"flutter" /C:"ActivityManager" /C:"ActivityTaskManager" /C:"DEBUG" /C:"libc" > "android-log-kurz.txt" 2>&1

echo.
echo  ==========================================================
echo   Fertig. Zwei Dateien sind entstanden:
echo.
echo     android-log.txt        vollstaendig
echo     android-log-kurz.txt   nur die interessanten Zeilen
echo.
echo   Bitte android-log-kurz.txt oeffnen und den Inhalt
echo   weitergeben. Kurz ist meistens aussagekraeftiger.
echo  ==========================================================
echo.
echo  Ordner: %CD%
echo.

start "" notepad "%CD%\android-log-kurz.txt"

pause
