chcp 65001
@echo off
pushd "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "AniDL_Search.ps1"
popd
pause