#!/bin/bash

# Default values
qemu_bin="qemu-system-x86_64"
data_dir="/tmp/qemu-vhost-user-test"
boot_img_url="https://cloud-images.ubuntu.com/groovy/current/groovy-server-cloudimg-amd64-disk-kvm.img"
test_img_size="32"
identity_file="$HOME/.ssh/id_rsa.pub"
guest_ip="192.168.1.2"
netmask="24"

show_help () {
        echo "Usage: ${0} [OPTIONS]"
	echo "Setup a data dir with all the files required to perform vhost-user tests"
	echo "Options:"
	echo -e "\t-q\tPath to a qemu binary. Defaults to ${qemu_bin}"
	echo -e "\t-c\tURL to a cloud image. Defaults to ${boot_img_url}"
	echo -e "\t-s\tSize (in GiB) of the test image for block. Defaults to ${test_img_size}"
	echo -e "\t-d\tDestination directory to store the files created. Defaults to ${data_dir}"
        echo -e "\t-k\tPath to the public key to allow for test user on VM. Defaults to ${identity_file}"
        echo -e "\t-i\tIP to assign to the TAP-based network interface in the guest. Defaults to ${guest_ip}"
        echo -e "\t-n\tNetmask to assign to the TAP-based network interface in the guest. Defaults to ${netmask}"
}

# A POSIX variable
OPTIND=1         # Reset in case getopts has been used previously in the shell.

while getopts "h?q:c:s:d:k:i:n::" opt; do
    case "$opt" in
    h|\?)
        show_help
        exit 0
        ;;
    q)  qemu_bin="$OPTARG"
	;;
    c)  boot_img_url="$OPTARG"
	;;
    s)  test_img_size="$OPTARG"
	;;
    d)  data_dir="$OPTARG"
	;;
    k)  identity_file="$OPTARG"
	;;
    i)  guest_ip="$OPTARG"
	;;
    n)  netmask="$OPTARG"
	;;
    esac
done

shift $((OPTIND-1))

tmpdir=$(mktemp -d)

# Check that we have the data folder
if [ ! -d ${data_dir} ]; then
	mkdir ${data_dir} || exit 1
fi

#Download OS image
wget ${boot_img_url} -O ${data_dir}/boot.img || exit 1

#Generate cloudiso image
./generate_nocloud_iso.sh -k ${identity_file} -i ${guest_ip} -n ${netmask} ${data_dir}/nocloud.iso || exit 1

#Generate raw image for virtio-block tests
dd if=/dev/zero of=${data_dir}/test.img bs=1MiB count=$(( ${test_img_size} * 1024 )) || exit 1

qemu_cmdline="-enable-kvm \
	-drive file=${data_dir}/boot.img,media=disk,if=ide \
	-drive file=${data_dir}/test.img,media=disk,if=virtio \
	-cdrom ${data_dir}/nocloud.iso \
	-nographic \
	-nic user,model=virtio-net-pci,mac=52:54:00:12:34:00 \
	-nic user,model=virtio-net-pci,mac=52:54:00:12:34:01 \
	-m 4G"

${qemu_bin} ${qemu_cmdline}

echo "All done! Goodbye!"
