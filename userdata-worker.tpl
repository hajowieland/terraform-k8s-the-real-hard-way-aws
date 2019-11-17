#!/bin/bash
sudo apt-get update
sudo apt-get upgrade -y
RANDOM_NUMBER=$(shuf -i 10-250 -n 1)
sudo POD_CIDR="${pod_cidr}.$RANDOM_NUMBER.0/24" >> /etc/environment
