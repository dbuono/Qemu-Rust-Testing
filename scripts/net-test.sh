#!/bin/bash
#
# Copyright (c) 2018 Intel Corporation
# 
# SPDX-License-Identifier: Apache-2.0
#
# Cut-down version of the kata metrics network test
# Originally available at
# https://github.com/kata-containers/tests/blob/master/metrics/network/network-metrics-iperf3.sh
#
# Changes by Daniele Buono
# Copyright (c) 2020 IBM Corporation

# Port number where the server will run
server_pid=""
server_log=""

transmit_timeout="${transmit_timeout:-120}"
server_address=192.168.1.2
host_port=9022
identity_file="$HOME/.ssh/id_rsa"

function start_server() {
	local ssh=${1}
	local dest=${2}
	local command=${3}
	local arguments=${4}
	echo "Starting iperf server. Log saved in ${server_log}"
	${ssh} ${dest} -t -t "${command} ${arguments}" >${server_log} 2>&1 &
	server_pid=$!
}

function server_running() {
	if [[ ( -d /proc/$server_pid ) && ( -z `grep zombie /proc/$server_pid/status` ) ]]; then
		echo "Server is running."
		return 0
	else
		echo "Server is not running. Log of start_server follows:"
		cat ${server_log}
		rm ${server_log}
		return 1
	fi
}

function stop_server() {
	kill $server_pid
	rm ${server_log}
}

function die() {
	echo ${1}
	exit 1
}

# Test single direction TCP bandwith
function iperf3_bandwidth() {
	local TEST_NAME="$1"

	# Verify server IP address
	if [ -z "$server_address" ];then
		die "server: ip address no found"
	fi

	# Start client
	local client_command="iperf3 -J -c ${server_address} -t ${transmit_timeout}"

	# Start server
	result=$($client_command)

	local bits_per_second=$(echo "$result" | jq '.end.sum_received.bits_per_second')
	local total_bandwidth=$(echo "scale=2 ; $bits_per_second / 1000000" | bc)

	echo "Test network bwd single direction TCP"	
	echo "Bandwidth (Mbps): $total_bandwidth"
}

# Test jitter on single direction UDP
function iperf3_jitter() {
	local TEST_NAME="$1"

	# Verify server IP address
	if [ -z "$server_address" ];then
		die "server: ip address no found"
	fi

	# Start server
	local client_command="iperf3 -J -c ${server_address} -u -t ${transmit_timeout}"
	result=$($client_command)

	local total_jitter=$(echo "$result" | jq '.end.sum.jitter_ms')

	echo "Test network jitter single direction UDP"	
	echo "Jitter (ms): $total_jitter"
}

# This function parses the output of iperf3 execution
function parse_iperf3_bwd() {
	local TEST_NAME="$1"
	local result="$2"

	if [ -z "$result" ]; then
		die "no result output"
	fi

 	# Getting results
	local rx_bwd=$(echo "$result" | jq '.end.sum_received.bits_per_second')
	local rx_bwd_mbps=$(echo "scale=2 ; $rx_bwd / 1000000" | bc)
	local tx_bwd=$(echo "$result" | jq '.end.sum_sent.bits_per_second')
	local tx_bwd_mbps=$(echo "scale=2 ; $tx_bwd / 1000000" | bc)

	echo "Test ${TEST_NAME}"	
	echo "RX Bandwidth (Mbps): $rx_bwd_mbps"
	echo "TX Bandwidth (Mbps): $tx_bwd_mbps"
}

# This function parses the output of iperf3 UDP execution, and
# saves the receiver successful datagram value in the results.
function parse_iperf3_pps() {
	local TEST_NAME="$1"
	local result="$2"

	if [ -z "$result" ]; then
		die "no result output"
	fi

	# Extract results
	local lost=$(echo "$result" | jq '.end.sum.lost_packets')
 	local total=$(echo "$result" | jq '.end.sum.packets')
	local notlost=$((total-lost))
	local pps=$((notlost/transmit_timeout))

	echo "Test ${TEST_NAME}"	
	echo "Received rate (pps): $pps"
	echo "Lost packets: $lost"
	echo "Total packets: $total"
	echo "Not lost packets: $notlost"
}

# This function launches a container that will take the role of
# server, this is order to attend requests from a client.
# In this case the client is an instance of iperf3 running in the host.
function get_host_cnt_bwd() {
	local cli_args="$1"

	# Verify server IP address
	if [ -z "$server_address" ];then
		die "server: ip address no found"
	fi

	# client test executed in host
	local output=$(iperf3 -J -c $server_address -t $transmit_timeout "$cli_args")

	echo "$output"
}

# Run a UDP PPS test between two containers.
# Use the smallest packets we can and run with unlimited bandwidth
# mode to try and get as many packets through as possible.
function get_cnt_cnt_pps() {
	local cli_args="$1"

	# Verify server IP address
	if [ -z "$server_address" ];then
		die "server: ip address no found"
	fi

	# and start the client container
	local client_command="iperf3 -J -u -c ${server_address} -l 64 -b 0 ${cli_args} -t ${transmit_timeout}"
	local output=$($client_command)

	echo "$output"
}

# Run a UDP PPS test between the host and a container, with the client on the host.
# Use the smallest packets we can and run with unlimited bandwidth
# mode to try and get as many packets through as possible.
function get_host_cnt_pps() {
	local cli_args="$1"

	# Verify server IP address
	if [ -z "$server_address" ];then
		die "server: ip address no found"
	fi

	# and start the client container
	local output=$(iperf3 -J -u -c $server_address -l 64 -b 0 -t $transmit_timeout "$cli_args")

	echo "$output"
}

# This test measures the bandwidth between a container and the host.
# where the container take the server role and the iperf3 client lives
# in the host.
function iperf3_host_cnt_bwd() {
	local TEST_NAME="network bwd host contr"
	local result="$(get_host_cnt_bwd)"
	parse_iperf3_bwd "$TEST_NAME" "$result"
}

# This test is similar to "iperf3_host_cnt_bwd", the difference is this
# tests runs in reverse mode.
function iperf3_host_cnt_bwd_rev() {
	local TEST_NAME="network bwd host contr reverse"
	local result="$(get_host_cnt_bwd "-R")"
	parse_iperf3_bwd "$TEST_NAME" "$result"
}

# This tests measures the bandwidth using different number of parallel
# client streams. (2, 4, 8)
function iperf3_multiqueue() {
	local TEST_NAME="network multiqueue"
	local client_streams=("2" "4" "8")

	for s in "${client_streams[@]}"; do
		tn="$TEST_NAME $s"
		result="$(get_host_cnt_bwd "-P $s")"
		parse_iperf3_bwd "$tn" "$result"
	done
}

# This test measures the packet-per-second (PPS) between the host and a container.
# It uses the smallest (64byte) UDP packet streamed with unlimited bandwidth
# to obtain the result.
function iperf3_host_cnt_pps() {
	local TEST_NAME="network pps host cnt"
	local result="$(get_host_cnt_pps)"
	parse_iperf3_pps "$TEST_NAME" "$result"
}

# This test measures the packet-per-second (PPS) between the host and a container.
# It runs iperf3 in 'Reverse' mode.
# It uses the smallest (64byte) UDP packet streamed with unlimited bandwidth
# to obtain the result.
function iperf3_host_cnt_pps_rev() {
	local TEST_NAME="network pps host cnt rev"
	local result="$(get_host_cnt_pps "-R")"
	parse_iperf3_pps "$TEST_NAME" "$result"
}

function help () {
	echo "Usage: ${0} [OPTION] DEST_DIR"
	echo "Run net tests on the VM".
	echo "Will write the results on DEST_DIR"
	echo "Options:"
	echo -e "\t-k\tPath to the public key to allow for test user on VM. Defaults to ${identity_file}"
	echo -e "\t-i\tGuest IP. Default of ${server_address}"
	echo -e "\t-s\tHost port to redirect to VM's ssh port. Default of ${host_port}"
	echo -e "\t-t\tSingle-Test time. Defaults to ${transmit_timeout}"
	echo -e ""
	echo -e "\t-a\tRun all tests"
	echo -e "\t-b\tRun all bandwidth tests"
	echo -e "\t-j\tRun jitter tests"
	echo -e "\t-p\tRun all PPS tests"
}

function main {
	local OPTIND
 	while getopts ":abh:jpt:k:i:t:s:" opt
	do
		case "$opt" in
		a)      # all tests
			test_bandwidth="1"
			test_jitter="1"
			test_pps="1"
			;;
		b)      # bandwidth tests
			test_bandwidth="1"
			;;
		h|\?)
			help
			exit 1;
			;;
		j)      # Jitter tests
			test_jitter="1"
			;;
		p)      # all PacketPerSecond tests
			test_pps="1"
			;;
		:)
			echo "Missing argument for -$OPTARG";
			help
			exit 1;
			;;
		k)  identity_file=$OPTARG
			;;
		i)  server_address=$OPTARG
			;;
		t)  transmit_timeout=$OPTARG
			;;
		s)  host_port=$OPTARG
			;;
		esac
	done
	shift $((OPTIND-1))

	if [ "$#" != "1" ]; then
		help
		exit 1
	fi

	ssh_cmd="ssh -i "${identity_file}" -p ${host_port} -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
	guest_addr="test@127.0.0.1"
	dest_dir=${1}
	server_log=${dest_dir}/server.log

	# Check that we have the destination folder
	if [ ! -d ${dest_dir} ]; then
		mkdir ${dest_dir} || exit 1
	fi


	[[ -z "$test_bandwidth" ]] && \
	[[ -z "$test_jitter" ]] && \
	[[ -z "$test_pps" ]] && \
		help && die "Must choose at least one test"

	start_server "${ssh_cmd}" "${guest_addr}" "iperf3" "-s"
	sleep 5
	server_running
	if [ "$?" != "0" ]; then
		echo "There was an error starting the server in the VM"
		die 1
	fi

	if [ "$test_bandwidth" == "1" ]; then
 		iperf3_bandwidth > ${dest_dir}/bandwidth.log
		iperf3_host_cnt_bwd >> ${dest_dir}/bandwidth.log
 		iperf3_host_cnt_bwd_rev >> ${dest_dir}/bandwidth.log
		iperf3_multiqueue >> ${dest_dir}/bandwidth.log
	fi

	if [ "$test_jitter" == "1" ]; then
		iperf3_jitter > ${dest_dir}/jitter.log
	fi

	if [ "$test_pps" == "1" ]; then
		iperf3_host_cnt_pps > ${dest_dir}/pps.log
		iperf3_host_cnt_pps_rev >> ${dest_dir}/pps.log
	fi

	stop_server
}

main "$@"
