@echo off
cd /d %~dp0
echo =========================================
echo  Deploiement Islamic Hub → RPi
echo =========================================
python deploy.py
pause
