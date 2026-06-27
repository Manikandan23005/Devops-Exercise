#!/usr/bin/env python3
import os
import json

print("Starting Dummy Application...")

current_dir = os.path.dirname(os.path.abspath(__file__))
config_path = os.path.join(current_dir, '../config/app.json')

try:
    with open(config_path, 'r') as f:
        config = json.load(f)
    print(f"Application started in {config.get('environment')} mode.")
    print(f"Database host: {config.get('db_host')}:{config.get('db_port')}")
except Exception as e:
    print(f"Failed to read configuration: {str(e)}")
