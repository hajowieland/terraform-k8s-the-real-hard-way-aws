#!/bin/bash
sudo yum update
sudo yum upgrade -y
wget https://gist.githubusercontent.com/dmytro/3984680/raw/1e25a9766b2f21d7a8e901492bbf9db672e0c871/ssh-multi.sh -O /home/ec2-user/tmux-multi.sh
chmod +x /home/ec2-user/tmux-multi.sh
wget https://pkg.cfssl.org/R1.2/cfssl_linux-amd64
chmod +x cfssl_linux-amd64
sudo mv cfssl_linux-amd64 /usr/local/bin/cfssl
wget https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64
chmod +x cfssljson_linux-amd64
sudo mv cfssljson_linux-amd64 /usr/local/bin/cfssljson
curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
chmod +x ./kubectl
sudo mv kubectl /usr/local/bin/kubectl
sudo hostname "${component}.${domain}"
