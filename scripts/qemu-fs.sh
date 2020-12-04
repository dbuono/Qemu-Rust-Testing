#!/bin/bash

# Default values
qemu_bin=qemu-system-x86_64
virtio_daemon_bin=virtiofsd
virtio_daemon_type=QEMU
boot_img=
data_dir=/tmp/qemu-vhost-user-test/
shared_folder=
host_port=9022

show_help () {
        echo "Usage: ${0} [OPTIONS]"
	echo "Options:"
	echo -e "\t-q\tPath to a qemu binary. Defaults to ${qemu_bin}"
	echo -e "\t-d\tPath to a virtio-user daemon binary. Defaults to ${virtio_daemon_bin}"
	echo -e "\t-v\tType of virtio backend to use. Can be either QEMU or CH (For Cloud-Hypervisor). Defaults to ${virtio_daemon_type}"
	echo -e "\t-p\tPath to a folder containing all the files required to perform the test. Defaults to ${data_dir}"
	echo -e "\t-f\tPath to the folder on the host to be shared. Overrides default of \$data_dir"
	echo -e "\t-b\tExplicitly select a boot image. Overrides default of \$data_dir/boot.img"
	echo -e "\t-s\tHost port to redirect to VM's ssh port. Default of ${host_port}"
}

# A POSIX variable
OPTIND=1         # Reset in case getopts has been used previously in the shell.

while getopts "h?q:d:v:p:b:s:f:" opt; do
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
    s)  host_port="$OPTARG"
	;;
    f)  shared_folder="$OPTARG"
	;;
    esac
done

shift $((OPTIND-1))

[ "${1:-}" = "--" ] && shift

if [ "${boot_img}" = "" ]; then
	boot_img="${data_dir}/boot.img"
fi

if [ "${shared_folder}" = "" ]; then
	shared_folder="${data_dir}"
fi

qemu_cmdline="-enable-kvm \
	-nographic \
	-nic user,model=virtio-net-pci,mac=52:54:00:12:34:00,hostfwd=tcp::${host_port}-:22 \
	-drive file=${boot_img},media=disk,if=ide \
	-m 4G -smp 4"
		
vhost_socket=$(mktemp)

qemu_cmdline="${qemu_cmdline} -chardev socket,id=char0,path=${vhost_socket} \
		-device vhost-user-fs-pci,queue-size=1024,chardev=char0,tag=myfs \
		-m 4G -object memory-backend-file,id=mem,size=4G,mem-path=/dev/shm,share=on -numa node,memdev=mem" 


case "${virtio_daemon_type}" in
	"QEMU")
		echo "Will use internal QEMU virtio block device"
		${virtio_daemon_bin} -f -o cache=auto -o source=${shared_folder} --socket-path=${vhost_socket} &
		;;
	"CH")
		echo "Will use Cloud-Hypervisor vhost-user fs device"
		${virtio_daemon_bin} --socket ${vhost_socket} --shared-dir ${shared_folder} &
		;;
	*)
		echo "Unrecognized virtio-fs daemon"
		exit 1
esac

${qemu_bin} ${qemu_cmdline}
