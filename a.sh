#!/bin/bash

# This function will be executed when SIGINT is received.
handle_sigint() {
  echo "SUCCESS: SIGINT signal received. Exiting."
  exit 0
}

# The 'trap' command registers the function to handle the INT signal.
trap 'handle_sigint' INT

echo "Test script running with PID: $$"
echo "Waiting for SIGINT (Ctrl-C)..."

# An infinite loop to keep the script alive until a signal is received.
while true; do
  sleep 1
done
