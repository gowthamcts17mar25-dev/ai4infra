#!/bin/bash

echo "Stopping CPU stress processes..."

pkill yes
pkill stress
pkill stress-ng

echo "CPU load removed."

top -bn1 | head -15
