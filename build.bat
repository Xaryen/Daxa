@echo off
setlocal

rem ============================================================================
rem  Builds the stripped-down Daxa DLL used by Lighthouse directly with cl.exe.
rem  No CMake, no Ninja.
rem
rem    - shared library      -> daxa.dll + daxa.lib + daxa.pdb
rem    - dynamic CRT (/MD)   -> same as the daxa.dll currently shipped with Lighthouse
rem    - no optional utils   -> task graph, mem, imgui, pipeline manager, fsr2 all OFF
rem    - no tests, no tools
rem    - no daxa asserts     -> DAXA_VALIDATION=0 (see the knob below)
rem
rem  Requirements:
rem    - Visual Studio 2022 with the C++ x64 build tools
rem    - Vulkan SDK, with the VULKAN_SDK environment variable set (the SDK installer does this)
rem    - VulkanMemoryAllocator is vendored in thirdparty\vma (no download needed)
rem
rem  Usage:   build.bat [release|debug]        (default: release = /O2 with a pdb)
rem  Output:  build\<config>\daxa.dll  daxa.lib  daxa.pdb
rem ============================================================================

set "CONFIG=%~1"
if "%CONFIG%"=="" set "CONFIG=release"
if /i "%CONFIG%"=="release" goto :config_ok
if /i "%CONFIG%"=="debug" goto :config_ok
echo Unknown configuration "%CONFIG%". Use release or debug.
exit /b 1
:config_ok

set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
set "OUT_DIR=%ROOT%\build\%CONFIG%"
set "OBJ_DIR=%OUT_DIR%\obj"

if not defined VULKAN_SDK (
    echo VULKAN_SDK is not set. Install the Vulkan SDK or point VULKAN_SDK at it.
    exit /b 1
)
if not exist "%VULKAN_SDK%\Lib\vulkan-1.lib" (
    echo "%VULKAN_SDK%\Lib\vulkan-1.lib" not found. Check VULKAN_SDK.
    exit /b 1
)

rem --- MSVC environment (skipped when already inside a developer prompt) ------
if defined DevEnvDir goto :msvc_ok

set "VS_INSTALLER=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer"
if not exist "%VS_INSTALLER%\vswhere.exe" (
    echo vswhere.exe not found. Run this script from an "x64 Native Tools Command Prompt".
    exit /b 1
)
for /f "usebackq tokens=*" %%i in (`"%VS_INSTALLER%\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VS_PATH=%%i"
if not defined VS_PATH (
    echo No Visual Studio installation with C++ build tools found.
    exit /b 1
)
rem vcvars64.bat expects vswhere.exe on PATH and complains otherwise.
set "PATH=%VS_INSTALLER%;%PATH%"
call "%VS_PATH%\VC\Auxiliary\Build\vcvars64.bat" >nul
if errorlevel 1 (
    echo vcvars64.bat failed.
    exit /b 1
)
:msvc_ok

rem Daxa internal asserts and validation (DAXA_DBG_ASSERT_TRUE_M, GPU id validation).
rem 0 = compiled out in both configs. Set to 1 to get the checks back.
set "DAXA_VALIDATION=0"

rem --- Flags ------------------------------------------------------------------
rem Core sources only. src\utils\*.cpp compile to nothing without the DAXA_BUILT_WITH_UTILS_* defines.
set SOURCES=^
 "%ROOT%\src\cpp_wrapper.cpp"^
 "%ROOT%\src\impl_device.cpp"^
 "%ROOT%\src\impl_features.cpp"^
 "%ROOT%\src\impl_instance.cpp"^
 "%ROOT%\src\impl_core.cpp"^
 "%ROOT%\src\impl_pipeline.cpp"^
 "%ROOT%\src\impl_swapchain.cpp"^
 "%ROOT%\src\impl_command_recorder.cpp"^
 "%ROOT%\src\impl_gpu_resources.cpp"^
 "%ROOT%\src\impl_sync.cpp"^
 "%ROOT%\src\impl_dependencies.cpp"^
 "%ROOT%\src\impl_timeline_query.cpp"

set INCLUDES=/I"%ROOT%\include" /I"%ROOT%\thirdparty\vma" /I"%VULKAN_SDK%\Include"

rem DAXA_CMAKE_EXPORT is what the public headers use to mark exported symbols.
set DEFINES=/DWIN32 /D_WINDOWS "/DDAXA_CMAKE_EXPORT=__declspec(dllexport)" /DDAXA_VALIDATION=%DAXA_VALIDATION%

set CXXFLAGS=/nologo /std:c++20 /permissive- /EHsc /GR /bigobj /MP /W4
set CXXFLAGS=%CXXFLAGS% /w14242 /w14254 /w14263 /w14265 /w14287 /we4289 /w14296 /w14311 /w14545 /w14546 /w14547 /w14549 /w14555 /w14619 /w14640 /w14826 /w14905 /w14906 /w14928

if /i "%CONFIG%"=="debug" (
    set CXXFLAGS=%CXXFLAGS% /Od /Z7 /MDd /RTC1
) else (
    set CXXFLAGS=%CXXFLAGS% /O2 /Z7 /MD /DNDEBUG
)

set LINKFLAGS=/nologo /DLL /MACHINE:X64 /DEBUG /INCREMENTAL:NO /OPT:REF /OPT:ICF
set LIBS="%VULKAN_SDK%\Lib\vulkan-1.lib" kernel32.lib

rem --- Compile ----------------------------------------------------------------
if not exist "%OBJ_DIR%" mkdir "%OBJ_DIR%"
del /q "%OBJ_DIR%\*.obj" >nul 2>&1

cl %CXXFLAGS% %DEFINES% %INCLUDES% /c /Fo"%OBJ_DIR%\\" %SOURCES%
if errorlevel 1 (
    echo.
    echo Compile failed.
    exit /b 1
)

rem --- Link -------------------------------------------------------------------
link %LINKFLAGS% /OUT:"%OUT_DIR%\daxa.dll" /IMPLIB:"%OUT_DIR%\daxa.lib" /PDB:"%OUT_DIR%\daxa.pdb" "%OBJ_DIR%\*.obj" %LIBS%
if errorlevel 1 (
    echo.
    echo Link failed.
    exit /b 1
)

echo.
echo Done: %OUT_DIR%\daxa.dll  (+ daxa.lib, daxa.pdb)
endlocal
