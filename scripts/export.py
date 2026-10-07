#!/usr/bin/env python3
"""Export current staged Yocto artifacts and evidence without deployment."""
import subprocess
import sys
subprocess.run(['python3', '/opt/orin-scripts/collect-yocto-evidence.py', sys.argv[1]], check=True)
