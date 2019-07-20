#! /bin/bash
ENV TZ=Europe/Berlin
ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
sudo apt-get update
sudo apt-get upgrade -y