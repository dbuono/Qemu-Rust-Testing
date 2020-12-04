#!/bin/bash
tmpdir=$(mktemp -d)
identity_file="$HOME/.ssh/id_rsa.pub"
guest_ip="192.168.1.2"
netmask="24"

show_help () {
        echo "Usage: ${0} [OPTION] DEST_FILE"
        echo "Create a nocloud cloud-config image to configure the VM"
	echo "Will write the config on DEST_FILE"
        echo "Options:"
        echo -e "\t-k\tPath to the public key to allow for test user on VM. Defaults to ${identity_file}"
        echo -e "\t-i\tIP to assign to the TAP-based network interface in the guest. Defaults to ${guest_ip}"
        echo -e "\t-n\tNetmask to assign to the TAP-based network interface in the guest. Defaults to ${netmask}"
}

# A POSIX variable
OPTIND=1         # Reset in case getopts has been used previously in the shell.

while getopts "h?i:k:n:" opt; do
    case "$opt" in
    h|\?)
        show_help
        exit 1
        ;;
    k)  identity_file=$OPTARG
        ;;
    i)  guest_ip=$OPTARG
	;;
    n)  netmask=$OPTARG
    esac
done

shift $((OPTIND-1))

[ "${1:-}" = "--" ] && shift

if [ "$#" != "1" ]; then
       show_help
       exit 1
fi

destfile=${1}

echo "Using temporary folder $tmpdir"

cat > $tmpdir/meta-data <<EOF
local-hostname: qemu-vhost-test
EOF
if [ $? -ne 0 ]; then
	exit 1
fi

cat > $tmpdir/network-config <<EOF
version: 2
ethernets:
  eth0:
    match:
      macaddress: '52:54:00:12:34:00'
    set-name: eth0
    dhcp4: true
  eth1:
    match:
      macaddress: '52:54:00:12:34:01'
    set-name: eth1
    addresses:
      - ${guest_ip}/${netmask}
EOF
if [ $? -ne 0 ]; then
	exit 1
fi

cat > $tmpdir/user-data <<EOF
#cloud-config

locale: en_US.UTF-8

users:
- name: test
  lock-passwd: false
  lock_passwd: false
  plain_text_passwd: test
  sudo: ALL=(ALL) NOPASSWD:ALL
  shell: /bin/bash
  ssh_authorized_keys:
    - $(cat ${identity_file})

packages :
 - iperf3
 - fio

runcmd :
  - echo 'type=83' | sfdisk /dev/vda
  - mkfs.ext4 /dev/vda1

power_state:
  message: VM Configuration is done. Shutting down...
  mode: poweroff
  timeout: 120
  condition: True
EOF
if [ $? -ne 0 ]; then
	exit 1
fi

genisoimage  -output $destfile -volid cidata -joliet -rock $tmpdir/user-data $tmpdir/meta-data  $tmpdir/network-config || exit 1

rm -R $tmpdir
