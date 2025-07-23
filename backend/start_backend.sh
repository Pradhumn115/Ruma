#!/bin/bash

# SuriAI Backend Startup Script with Crash Protection
# ==================================================

echo "🚀 Starting SuriAI Backend with Crash Protection..."

# Method 1: Use the crash guardian (recommended for production)
echo "🛡️ Starting with Crash Guardian..."
python3 crash_guardian.py --script unified_app.py --max-restarts 10 --restart-delay 5

# Alternative: Direct startup with basic protection
# echo "🔧 Starting with basic protection..."
# python3 unified_app.py