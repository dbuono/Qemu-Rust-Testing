#!/bin/bash

# Default values
qemu_bin=qemu-system-x86_64
virtio_daemon_bin=vhost_user_block
virtio_daemon_type=QEMU
boot_img=
tapname=testtap0
data_dir=/tmp/qemu-vhost-user-test/
host_port=9022
hostip=192.168.1.1
netmask=24
vhost_socket=""

cidr2mask ()
{
	local cidr=${1}
	local decval=0
	local bitcount=8
	declare -a netmask=()
	for (( i = ${cidr} ; i >0; i--)); do
		decval=$(( ${decval} + (2 ** (${bitcount}-1)) ));
		bitcount=$(( ${bitcount} - 1 ))
		if [ "${bitcount}" = "0" ]; then
			netmask+=("${decval}")
			bitcount=8
			decval=0
		fi
	done
	if [ "${bitcount}" -lt "8" ]; then
		netmask+=("${decval}")
	fi
    	echo ${netmask[0]:-0}.${netmask[1]:-0}.${netmask[2]:-0}.${netmask[3]:-0}
}

show_help () {
        echo "Usage: ${0} [OPTIONS]"
	echo "Start qemu with a tap-based virtio network"
	echo "Options:"
	echo -e "\t-q\tPath to a qemu binary. Defaults to ${qemu_bin}"
	echo -e "\t-d\tPath to a virtio-user daemon binary. Defaults to ${virtio_daemon_bin}"
	echo -e "\t-v\tType of virtio backend to use. Can be either QEMU or CH (For Cloud-Hypervisor). Defaults to ${virtio_daemon_type}"
	echo -e "\t-p\tPath to a folder containing all the files required to perform the test. Defaults to ${data_dir}"
	echo -e "\t-b\tExplicitly select a boot image. Overrides default of \$data_dir/boot.img"
	echo -e "\t-h\tHost tap IP address. Defaults to ${hostip}"
	echo -e "\t-n\tHost tap netmask. Defaults to ${netmask}"
	echo -e "\t-s\tHost port to redirect to VM's ssh port. Default of ${host_port}"
}

# A POSIX variable
OPTIND=1         # Reset in case getopts has been used previously in the shell.

while getopts "h?q:d:v:p:b:h:n:s:" opt; do
    case "$opt" in
    h|\?)
        show_help
        exit 0
        ;;
    q)  qemu_bin="$OPTARG"
	;;
    d)  virtio_daemon_bin="$OPTARG"
	;;
    v)  virtio_daemon_type="$OPTARG"
	;;
    p)  data_dir="$OPTARG"
	;;
    b)  boot_img="$OPTARG"
	;;
    h)  hostip="$OPTARG"
	;;
    n)  netmask="$OPTARG"
	;;
    s)  host_port="$OPTARG"
        ;;
    esac
done

shift $((OPTIND-1))

[ "${1:-}" = "--" ] && shift

if [ "${boot_img}" = "" ]; then
	boot_img="${data_dir}/boot.img"
fi

qemu_cmdline="-enable-kvm \
	-nographic \
	-nic user,model=virtio-net-pci,mac=52:54:00:12:34:00,hostfwd=tcp::${host_port}-:22 \
	-drive file=${boot_img},media=disk,if=ide \
	-m 4G -smp 4"

case "${virtio_daemon_type}" in
	"QEMU")
		echo "Will use internal QEMU virtio network device"
		qemu_cmdline="${qemu_cmdline} -netdev tap,id=mynet0,ifname=${tapname},script=no,downscript=no -device virtio-net-pci,netdev=mynet0,mac=52:54:00:12:34:01"
		;;
	"CH")
		echo "Will use Cloud-Hypervisor vhost-user block device"
		vhost_socket=$(mktemp)
		#Convert netmask from CIDR notation
		chnetmask=$(cidr2mask ${netmask})
		${virtio_daemon_bin} --net-backend "socket=${vhost_socket},ip=${hostip},mask=${chnetmask},num_queues=2,queue_size=512,tap=${tapname}" &
		qemu_cmdline="${qemu_cmdline} -chardev socket,id=char0,path=${vhost_socket} \
			-netdev vhost-user,chardev=char0,id=vhusernet0,queues=2 \
			-device virtio-net-pci,netdev=vhusernet0,mac=52:54:00:12:34:01 \
			-object memory-backend-file,id=mem,size=4G,mem-path=/dev/shm,share=on -numa node,memdev=mem"
		;;
	*)
		echo "Unrecognized virtio-block daemon"
		exit 1
esac

if [ "${virtio_daemon_type}" = "QEMU" ]; then
	echo "Creating tap device ${tapname}"
	#ip tuntap add name ${tapname} mode tap multi_queue
	user=$(whoami)
	sudo ip tuntap add dev ${tapname} mode tap user ${user}
	sleep 5
	sudo ifconfig ${tapname} ${hostip}/${netmask}
	sleep 5
fi

${qemu_bin} ${qemu_cmdline}

if [ "${virtio_daemon_type}" = "QEMU" ]; then
	echo "Deleting tap device ${tapname}"
	sudo ip tuntap del dev ${tapname} mode tap
fi
