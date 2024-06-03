#!/bin/bash

if [ $# -ne 1 ]; then
  echo "Usage: $0 <minutes>"
  exit 1
fi

clear

minutes=$1
end_time=$(date -j -v +${minutes}M +%s)

while [ $(date +%s) -lt $end_time ]; do
  remaining_seconds=$((end_time - $(date +%s)))
  hours=$((remaining_seconds / 3600))
  minutes=$(( (remaining_seconds % 3600) / 60 ))
  seconds=$((remaining_seconds % 60))

  if [ $remaining_seconds -lt 60 ]; then
   printf "\r\033[K\033[31m%02d\033[0m\r" $seconds
  elif [ $remaining_seconds -lt 3600 ]; then
    printf "\r\033[K\033[33m%02d:%02d\033[0m\r" $minutes $seconds
  else
    printf "\r%02d:%02d:%02d\r" $hours $minutes $seconds
  fi

  sleep 1
done

printf "\r\033[K\033[31mSTOP\033[0m\r"

while true; do
  read -r -s -n 1 -t 1
done
