@echo off
REM Time Trak - Windows ZIP Builder
REM This script creates a production-ready ZIP package for Windows

setlocal enabledelayedexpansion
cd /d "%~dp0"
echo.
echo ====================================
echo   Time Trak - Windows Build Script  
echo ====================================
echo.

REM Configuration
set APP_NAME=time_trak
set DISPLAY_NAME=TimeTrak
set VERSION=1.8.4
set BUILD_DIR=build\windows\x64\runner\Release
set PACKAGE_DIR=build\windows_package
set ZIP_NAME=TimeTrak-Windows-v%VERSION%.zip

echo [1/5] Cleaning previous builds...

REM Kill any lingering processes that might lock build files
echo Killing any lingering build processes...
taskkill /F /IM msbuild.exe /T >nul 2>&1
taskkill /F /IM flutter.exe /T >nul 2>&1
taskkill /F /IM cmake.exe /T >nul 2>&1
taskkill /F /IM cl.exe /T >nul 2>&1
taskkill /F /IM link.exe /T >nul 2>&1
taskkill /F /IM vctip.exe /T >nul 2>&1
taskkill /F /IM mspdbsrv.exe /T >nul 2>&1

REM Wait for file handles to be released
echo Waiting for file handles to release...
ping -n 4 127.0.0.1 >nul

REM Clean build directories more aggressively
echo Cleaning build directories...
if exist "%PACKAGE_DIR%" (
    rmdir /s /q "%PACKAGE_DIR%" 2>nul
    ping -n 2 127.0.0.1 >nul
)
if exist "build\%ZIP_NAME%" (
    del /f /q "build\%ZIP_NAME%" 2>nul
)

REM Try to clean the entire windows build directory to avoid file locking
if exist "build\windows" (
    echo Removing old Windows build directory...
    rmdir /s /q "build\windows" 2>nul
    ping -n 3 127.0.0.1 >nul
)



echo.
echo [2/5] Building Flutter Windows app (Release mode)...
echo.
echo NOTE: You may see CMake INSTALL errors - these can be safely ignored.
echo The build will succeed as long as the executable is created.
echo.

REM Clean Flutter cache first to avoid ZIP decompression errors
echo Cleaning Flutter cache...
call flutter clean
timeout /t 2 /nobreak >nul

REM Get fresh dependencies
echo Getting dependencies...
call flutter pub get

REM Build the Windows app
echo Building Windows application...
REM The INSTALL target may fail due to permissions, but the build itself will succeed
call flutter build windows --release --dart-define-from-file=.env

REM Check if executable was created (this is what matters)
if exist "%BUILD_DIR%\%APP_NAME%.exe" (
    echo.
    echo ========================================
    echo Build completed successfully - Executable found
    echo NOTE: You can ignore any INSTALL errors above.
    echo ========================================
    echo.
    goto build_success
)

REM If executable not found, try rebuilding
echo.
echo Executable not found. Attempting rebuild...
echo Getting dependencies again...
call flutter pub get
timeout /t 2 /nobreak >nul

echo Building Windows application (attempt 2)...
call flutter build windows --release --dart-define-from-file=.env

REM Check again for executable
if exist "%BUILD_DIR%\%APP_NAME%.exe" (
    echo.
    echo ========================================
    echo Build completed successfully - Executable found
    echo ========================================
    echo.
    goto build_success
)

REM Final check - if still no executable, then it's a real failure
if not exist "%BUILD_DIR%\%APP_NAME%.exe" (
    echo.
    echo ========================================
    echo ERROR: Build failed - No executable found.
    echo ========================================
    echo.
    echo Executable not found at: %BUILD_DIR%\%APP_NAME%.exe
    echo.
    echo Troubleshooting steps:
    echo 1. Ensure Visual Studio 2019 or later is installed
    echo 2. Make sure Windows SDK is installed
    echo 3. Run: flutter doctor -v
    echo 4. Check the build output above for errors
    echo.
    pause
    exit /b 1
)

:build_success
echo.
echo [3/5] Build successful - Copying files...

REM Ensure package directory exists
if not exist "%PACKAGE_DIR%" mkdir "%PACKAGE_DIR%" 2>nul

REM Copy the executable
copy "%BUILD_DIR%\%APP_NAME%.exe" "%PACKAGE_DIR%\%DISPLAY_NAME%.exe"

REM Copy all DLL files
echo Copying required DLLs...
for %%f in ("%BUILD_DIR%\*.dll") do (
    echo - %%~nxf
    copy "%%f" "%PACKAGE_DIR%\"
)

REM Copy plugin DLLs from each plugin Release folder
echo Copying plugin DLLs...
for /d %%p in ("build\windows\x64\plugins\*") do (
    if exist "%%p\Release\*.dll" (
        for %%f in ("%%p\Release\*.dll") do (
            echo - %%~nxf
            copy "%%f" "%PACKAGE_DIR%\"
        )
    )
)

REM Copy data directory (contains ICU data, etc.)
if exist "%BUILD_DIR%\data" (
    echo Copying data directory...
    xcopy "%BUILD_DIR%\data" "%PACKAGE_DIR%\data\" /E /I /Y /Q
)

REM Create README file
echo.
echo [4/5] Creating README file...
(
echo ====================================
echo   Time Trak - Windows Installation
echo ====================================
echo.
echo Version: %VERSION%
echo.
echo INSTALLATION INSTRUCTIONS:
echo 1. Extract all files from this ZIP to a folder of your choice
echo 2. Run TimeTrak.exe to start the application
echo.
echo SYSTEM REQUIREMENTS:
echo - Windows 10 or later
echo - 64-bit processor
echo.
echo NOTES:
echo - All files in this folder are required for the application to run
echo - Do not delete or move individual files
echo - You can create a desktop shortcut to TimeTrak.exe
echo.
echo For support or issues, please contact the developer.
echo.
echo Generated on: %date% %time%
) > "%PACKAGE_DIR%\README.txt"

REM Create a launcher batch file (optional, for running from any directory)
(
echo @echo off
echo cd /d "%%~dp0"
echo start "" "TimeTrak.exe"
) > "%PACKAGE_DIR%\Launch.bat"

echo.
echo [5/5] Creating ZIP archive...

REM Check if PowerShell is available (it should be on all modern Windows)
where powershell >nul 2>nul
if %errorlevel% equ 0 (
    powershell -command "Compress-Archive -Path '%PACKAGE_DIR%\*' -DestinationPath 'build\%ZIP_NAME%' -Force"

    if exist "build\%ZIP_NAME%" (
        echo.
        echo ====================================
        echo   BUILD SUCCESSFUL
        echo ====================================
        echo.
        echo Package created: build\%ZIP_NAME%
        echo Package size:
        for %%A in ("build\%ZIP_NAME%") do echo   %%~zA bytes
        echo.
        echo Contents:
        echo   - TimeTrak.exe ^(main executable^)
        echo   - Required DLL files
        echo   - Data directory
        echo   - README.txt
        echo   - Launch.bat
        echo.

        REM Copy to Desktop if desired
        set DESKTOP=%USERPROFILE%\Desktop
        if exist "!DESKTOP!" (
            echo Copying ZIP to Desktop...
            copy "build\%ZIP_NAME%" "!DESKTOP!\%ZIP_NAME%" >nul
            echo Done: !DESKTOP!\%ZIP_NAME%
        )

        echo.
        echo The application is ready for distribution!
        echo.
    ) else (
        echo.
        echo ERROR: Failed to create ZIP archive
        echo.
    )
) else (
    echo.
    echo ERROR: PowerShell not found. Cannot create ZIP archive.
    echo Please install PowerShell or manually zip the contents of:
    echo %PACKAGE_DIR%
    echo.
)

echo.
pause
