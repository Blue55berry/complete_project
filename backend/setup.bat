@echo off
REM RiskGuard Backend - Virtual Environment Setup Script
REM Run this script from the backend folder

echo.
echo ========================================
echo   RiskGuard Backend Setup
echo ========================================
echo.

REM Check Python version
echo [1/5] Checking Python version...
python --version
echo.

REM Create virtual environment
echo [2/5] Creating virtual environment...
if exist "venv" (
    echo Virtual environment already exists. Skipping creation.
) else (
    python -m venv venv
    echo Virtual environment created!
)
echo.

REM Activate virtual environment
echo [3/5] Activating virtual environment...
call venv\Scripts\activate.bat
echo.

REM Upgrade pip
echo [4/5] Upgrading pip...
python -m pip install --upgrade pip
echo.

REM Install requirements
echo [5/5] Installing requirements...
pip install -r requirements.txt
echo.

echo ========================================
echo   Setup Complete!
echo ========================================
echo.
echo To activate the virtual environment:
echo     venv\Scripts\activate
echo.
echo To run the backend:
echo     python main.py
echo.
echo Don't forget to create a .env file with:
echo     HF_TOKEN=your_huggingface_token_here
echo.
pause
