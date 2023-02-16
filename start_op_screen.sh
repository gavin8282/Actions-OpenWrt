#!/bin/bash

# Check if there is a running screen session
if screen -list | grep -q "op"; then
  # If "op" session exists, attach to it
  screen -r op
else
  # If "op" session does not exist, create a new one
  screen -dmS op bash -c 'sleep 1; rm -rf ~/g-openwrt && git clone https://github.com/4860575/g-openwrt.git && cd ~/g-openwrt && ./scripts/feeds update -a && ./scripts/feeds install -a && cp ~/*.config ~/g-openwrt/.config && make download -j$(nproc) && make V=s -j$(nproc) && exit'
fi
