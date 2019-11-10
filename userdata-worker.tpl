#!/bin/bash
sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get install -y python3-pip
sudo pip3 install awscli boto3 requests
cat > /usr/local/bin/attach-eni.py <<"EOF"
#!/bin/env python3

## https://aws.amazon.com/premiumsupport/knowledge-center/ec2-ubuntu-secondary-network-interface/
## https://aws.amazon.com/premiumsupport/knowledge-center/attach-second-eni-auto-scaling/

import boto3
import botocore
import requests
import logging
import subprocess


eni_list = []
%{ for eni in eni_ids ~}
eni_list.append('${eni}')
%{ endfor ~}

encoding = 'utf-8'
ec2_client = boto3.client('ec2', region_name='${aws_region}')

response_id = requests.get('http://169.254.169.254/latest/meta-data/instance-id')
instance_id = response.text

response_az = requests.get('http://169.254.169.254/latest/meta-data/placement/availability-zone')
availability_zone = response.text

result = ec2_client.describe_network_interfaces(
    Filters=[
        {
            'Name': 'status',
            'Values': [
                'available',
            ]
        },
        {
            'Name': 'availability-zone',
            'Values': [
                availability_zone
            ]
        }
    ],
)
eni_dict = {}
eni_describe_list = result['NetworkInterfaces']

for eni in eni_describe_list:
    eni_dict[eni['NetworkInterfaceId']] = eni['PrivateIpAddress']

attachment = None

attached_eni = ''

for eniid in eni_dict:
    try:
        attach_interface = ec2_client.attach_network_interface(
            NetworkInterfaceId=eniid,
            InstanceId=instance_id,
            DeviceIndex=1
        )
        attachment = attach_interface['AttachmentId']
        print("Create network attachment: {}".format(attachment.rstrip()))
        attached_eni = eniid
        break
    except botocore.exceptions.ClientError as e:
        logging.error("Error attaching network interface: {}".format(e.response['Error']))

result = ec2_client.describe_network_interfaces(
    Filters=[
        {
            'Name': 'network-interface-id',
            'Values': [
                attached_eni
            ]
        }
    ],
)
eni_tmp_list = result['NetworkInterfaces']
eni_dict = eni_tmp_list[0]
eni_ip = eni_dict['PrivateIpAddress']

ip_command = "ip route | awk '/default/ { print $3 }'"
gateway_raw = subprocess.check_output(ip_command, shell=True)
print("DEBUG: Gateway: {}".format(gateway_raw.decode(encoding).rstrip()))
gateway = gateway_raw.decode(encoding).rstrip()

netplanconfig = """
network:
  version: 2
  renderer: networkd
  ethernets:
    ens6:
      addresses:
       - {ipaddress}/24
      dhcp4: no
      routes:
       - to: 0.0.0.0/0
         via: {gatewayip}
         table: 1000
       - to: {ipaddress}
         via: 0.0.0.0
         scope: link
         table: 1000
      routing-policy:
        - from: {ipaddress}
          table: 1000
""".format(ipaddress=eni_ip, gatewayip=gateway)

print("Netplan Config:\n")
print(netplanconfig)

with open('/etc/netplan/51-ens6.yaml', 'a') as the_file:
    the_file.write(netplanconfig)

netplan_command = "netplan --debug apply"
command_output = subprocess.check_output(netplan_command, shell=True)
print("DEBUG: Netplan output {}".format(command_output.decode(encoding)))

EOF
sudo python3 /usr/local/bin/attach-eni.py