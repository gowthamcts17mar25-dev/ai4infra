#!/bin/bash

echo "Creating CPU stress"

for i in {1..4}
do
  yes > /dev/null &
done

echo "CPU stress started"

top -bn1 | head -15
