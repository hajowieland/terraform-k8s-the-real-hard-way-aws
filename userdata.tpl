#!/bin/bash
sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get install python3-pip -y
sudo pip3 install awscli
echo "AWS_DEFAULT_REGION=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | grep region | awk -F\" '{print $4}')" | sudo tee -a /etc/environment
echo "HOSTEDZONE_NAME=${domain}" | sudo tee -a /etc/environment
echo "INTERNAL_IP=$(curl -s http://169.254.169.254/1.0/meta-data/local-ipv4)" | sudo tee -a /etc/environment