#!/bin/bash
identity_file="$HOME/.ssh/id_rsa"
host_port=9022
size="8g"

show_help () {
        echo "Usage: ${0} [OPTION] DEST_DIR"
        echo "Run fio tests on the VM with virtiofs".
	echo "Will write the results on DEST_DIR"
        echo "Options:"
        echo -e "\t-k\tPath to the public key to allow for test user on VM. Defaults to ${identity_file}"
        echo -e "\t-s\tHost port to redirect to VM's ssh port. Default of ${host_port}"
        echo -e "\t-S\tTest file size. 4 Jobs will be run concurrently, each on a different file. Requires 4x this size in free space on the virtual image.  Defaults to ${size}"
}

# A POSIX variable
OPTIND=1         # Reset in case getopts has been used previously in the shell.

while getopts "h?k:s:S:" opt; do
    case "$opt" in
    h|\?)
        show_help
        exit 1
        ;;
    k)  identity_file=$OPTARG
        ;;
    s)  host_port=$OPTARG
	;;
    S)  size=$OPTARG
	 ;;
    esac
done

shift $((OPTIND-1))

[ "${1:-}" = "--" ] && shift

if [ "$#" != "1" ]; then
       show_help
       exit 1
fi

ssh_cmd="ssh -i "${identity_file}" -p ${host_port} -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
scp_cmd="scp -i ${identity_file} -P ${host_port} -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
guest_addr="test@127.0.0.1"
dest_dir=${1}

host_tmpdir=$(mktemp -d)
echo "Using temporary folder $host_tmpdir on host"
guest_tmpdir=$(${ssh_cmd} ${guest_addr} mktemp -d)
echo "Using temporary folder $guest_tmpdir on guest"
echo "Saving Results in ${dest_dir}"

# Check that we have the destination folder
if [ ! -d ${dest_dir} ]; then
        mkdir ${dest_dir} || exit 1
fi

#Create fio test scripts
for op in randread randwrite read write; do
	cat > $host_tmpdir/test-$op.fio <<EOF
[global]
; Parameters common to all test environments
; Ensure that jobs run for a specified time limit, not I/O quantity
time_based=1
runtime=120s
ramp_time=10s
; To model application load at greater scale, each test client will maintain
; a number of concurrent I/Os.
ioengine=libaio
iodepth=8
; Note: these two settings are mutually exclusive
; (and may not apply for Windows test clients)
; Set a number of workers on this client
thread=0
numjobs=4
group_reporting=1
; Each file for each job thread is this size
size=${size}
filename_format=\$jobnum.dat
[fio-job]
; FIO_RW is read, write, randread or randwrite
rw=${op}
EOF
	if [ $? -ne 0 ]; then
		exit 1
	fi
	done

${scp_cmd} ${host_tmpdir}/*.fio ${guest_addr}:${guest_tmpdir}/ || exit 1

${ssh_cmd} ${guest_addr} sudo modprobe virtiofs || exit 1
${ssh_cmd} ${guest_addr} sudo mount -t virtiofs myfs /mnt || exit 1

for op in randread randwrite read write; do
	echo Running test $op...
	${ssh_cmd} ${guest_addr} sudo fio ${guest_tmpdir}/test-$op.fio --fallocate=none --directory=/mnt --output-format=json+ --blocksize=65536 --output=${guest_tmpdir}/results-${op}.json || exit 1
done

${ssh_cmd} ${guest_addr} sudo umount /mnt || exit 1

${scp_cmd} ${guest_addr}:${guest_tmpdir}/*.json ${dest_dir} || exit 1
