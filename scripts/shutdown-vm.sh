#!/bin/bash
identity_file="$HOME/.ssh/id_rsa"
host_port=9022

show_help () {
        echo "Usage: ${0} [OPTIONS]"
        echo "Shutdown a VM through an SSH command"
        echo "Options:"
        echo -e "\t-k\tPath to the public key to allow for test user on VM. Defaults to ${identity_file}"
        echo -e "\t-s\tHost port to redirect to VM's ssh port. Default of ${host_port}"
}

# A POSIX variable
OPTIND=1         # Reset in case getopts has been used previously in the shell.

while getopts "h?k:s:" opt; do
    case "$opt" in
    h|\?)
        show_help
        exit 1
        ;;
    k)  identity_file=$OPTARG
        ;;
    s)  host_port=$OPTARG
    esac
done

shift $((OPTIND-1))

ssh_cmd="ssh -i "${identity_file}" -p ${host_port} -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
guest_addr="test@127.0.0.1"

${ssh_cmd} ${guest_addr} sudo shutdown -h now
