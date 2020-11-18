#!/bin/sh

# Default values
qemu_bin=qemu-system-x86_64
virtio_daemon_bin=
virtio_daemon_type=QEMU
cloudinit_img=
boot_img=
test_img=
tapname=mytap2
#tapname=tap2
hostip=192.168.1.1
netmask=255.255.255.0
vhost_socket=""

show_help () {
        echo "Usage: ${0} [OPTION] ... [BOOT_IMAGE] [TEST_IMAGE]"
	echo "Start qemu with a folder shared through virtiofsd"
	echo "BOOT_IMAGE is mandatory and is the OS image to boot in the VM"
	echo "Options:"
	echo "\t-q\tPath to a qemu binary. Defaults to ${qemu_bin}"
	echo "\t-d\tPath to a virtio-user daemon binary."
	echo "\t-c\tPath to a cloud-init image. If not provided, no cloud-init image will be used"
	echo "\t-v\tType of virtio backend to use. Can be either QEMU or CH (For Cloud-Hypervisor)"
}

# A POSIX variable
OPTIND=1         # Reset in case getopts has been used previously in the shell.

while getopts "h?q:d:v:c:" opt; do
    case "$opt" in
    h|\?)
        show_help
        exit 0
        ;;
    q)  qemu_bin=$OPTARG
	;;
    d)  virtio_daemon_bin=$OPTARG
	;;
    c)  cloudinit_img=$OPTARG
	;;
    v)  virtio_daemon_type=$OPTARG
	;;
    esac
done

shift $((OPTIND-1))

[ "${1:-}" = "--" ] && shift

if [ "$#" != "2" ]; then
	show_help
	exit 0
fi

boot_img=${1}
test_img=${2}

qemu_cmdline="-enable-kvm \
	-drive file=${boot_img},media=disk,if=ide \
	-nographic \
	-nic user,model=virtio-net-pci,hostfwd=tcp::9022-:22 \
	-m 4G -smp 4 \
	-drive file=${test_img},if=ide"

if [ "${cloudinit_img}" != "" ]; then
	qemu_cmdline="${qemu_cmdline} -drive file=${cloudinit_img},if=ide"
fi

case "${virtio_daemon_type}" in
	"QEMU")
		echo "Will use internal QEMU virtio network device"
		qemu_cmdline="${qemu_cmdline} -netdev tap,id=mynet0,ifname=${tapname},script=no,downscript=no -device virtio-net-pci,netdev=mynet0"
		;;
	"CH")
		echo "Will use Cloud-Hypervisor vhost-user block device"
		vhost_socket=$(mktemp)
		${virtio_daemon_bin} --net-backend "socket=${vhost_socket},ip=${hostip},mask=${netmask},num_queues=2,queue_size=512,tap=${tapname}" &
		qemu_cmdline="${qemu_cmdline} -chardev socket,id=char0,path=${vhost_socket} \
			-netdev vhost-user,chardev=char0,id=vhusernet0,queues=2 \
			-device virtio-net-pci,netdev=vhusernet0 \
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
	sudo ifconfig ${tapname} ${hostip}
	sleep 5
fi

${qemu_bin} ${qemu_cmdline}

if [ "${virtio_daemon_type}" = "QEMU" ]; then
	echo "Deleting tap device ${tapname}"
	sudo ip tuntap del dev ${tapname} mode tap
fi
