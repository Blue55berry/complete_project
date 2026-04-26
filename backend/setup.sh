#!/bin/bash
# RiskGuard Backend - Virtual Environment Setup Script (Unix/Mac)
# Run this script from the backend folder

echo ""
echo "========================================"
echo "  RiskGuard Backend Setup"
echo "========================================"
echo ""

# Check Python version
echo "[1/5] Checking Python version..."
python3 --version
echo ""

# Create virtual environment
echo "[2/5] Creating virtual environment..."
if [ -d "venv" ]; then
    echo "Virtual environment already exists. Skipping creation."
else
    python3 -m venv venv
    echo "Virtual environment created!"
fi
echo ""

# Activate virtual environment
echo "[3/5] Activating virtual environment..."
source venv/bin/activate
echo ""

# Upgrade pip
echo "[4/5] Upgrading pip..."
pip install --upgrade pip
echo ""

# Install requirements
echo "[5/5] Installing requirements..."
pip install -r requirements.txt
echo ""

echo "========================================"
echo "  Setup Complete!"
echo "========================================"
echo ""
echo "To activate the virtual environment:"
echo "    source venv/bin/activate"
echo ""
echo "To run the backend:"
echo "    python main.py"
echo ""
echo "Don't forget to create a .env file with:"
echo "    HF_TOKEN=your_huggingface_token_here"
echo ""
