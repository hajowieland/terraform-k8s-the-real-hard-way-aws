#!/bin/env bash
sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get install python3-pip -y
pip3 install awscli
wget https://pkg.cfssl.org/R1.2/cfssl_linux-amd64
chmod +x cfssl_linux-amd64
sudo mv cfssl_linux-amd64 /usr/local/bin/cfssl
wget https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64
chmod +x cfssljson_linux-amd64
sudo mv cfssljson_linux-amd64 /usr/local/bin/cfssljson
sudo hostname " + "${component}" + str(x + 1) + "." + "internal." + ${domain},
