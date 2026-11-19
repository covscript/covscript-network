@echo off
if not exist cmake-build\mingw-w64 mkdir cmake-build\mingw-w64
cd    cmake-build\mingw-w64
cmake -G "MinGW Makefiles" ..\..
if errorlevel 1 exit /b 1
cmake --build . -- -j4
if errorlevel 1 exit /b 1
cd ..\..
rd /S /Q build
mkdir build\imports
xcopy /Y cmake-build\mingw-w64\*.cse build\imports\
