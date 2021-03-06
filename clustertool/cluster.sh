#!/bin/bash

# 
# cluster.sh storage cluster control tool
# author: Michal Liszcz
# 
# similar to Erlang nodetool, but controls all the nodes
# in $CWD, allowing to start, stop or ping whole cluster
#
# examples:
# 	cluster.sh start			- start all nodes
# 	cluster.sh --node ds2 ping 	- ping node ds2
#

CWD="$( cd "$( dirname "$0" )" && pwd )"

function print_usage {
	cat <<<\
"usage: $0 [ -n <node> ] command
commands:
    start                    
    start_boot <file>        (node only)
    foreground               (node only)
    stop
    restart
    reboot
    ping
    console                  (node only)
    getpid
    console_clean            (node only)
    console_boot <file>      (node only)
    attach                   (node only)
    remote_console           (node only)
    upgrade                  (node only)
    clean                    "
}

ARGS=$(getopt -n "$0" -o hn: -l "help,node:" -- "$@" 2>/dev/null)

if [ $? -ne 0 ]
then
	print_usage
	exit 1
fi

OPT_NODE=""
MASS_ARGS=()

eval set -- "$ARGS"

while true
do
	case "$1" in
		-h|--help)
			shift
			print_usage
			exit 0
			;;
		-n|--node)
			shift
			if [ -f "$CWD/$1/bin/storage" ]; then
				OPT_NODE=$1
				shift
			else
				echo "'$1' is not a storage node"
				exit 1
			fi
			;;
		--)
			shift
			break
			;;
	esac
done


OPT_CLEAN=0
for i; do
	[ "$1" == "clean" ] && OPT_CLEAN=1
	MASS_ARGS+=($i)
done


if (( OPT_CLEAN ))
then
	for node in $([ -n "$OPT_NODE" ] && echo $OPT_NODE || ls $CWD)
	do
		[ -f "$CWD/$node/bin/storage" ] && \
			echo "removing $node data" && \
			rm -rf $CWD/$node/work_dir/* > /dev/null 2>&1
	done
	exit 0
fi


if [ -n "$OPT_NODE" ]
then
	$CWD/$OPT_NODE/bin/storage ${MASS_ARGS[@]}
elif [[ "start stop restart reboot ping getpid" =~ $MASS_ARGS ]]
then
	for node in $(ls $CWD)
	do
		[ -f "$CWD/$node/bin/storage" ] && \
			printf "$node: " && \
			$CWD/$node/bin/storage $MASS_ARGS
	done
else
	print_usage
	exit 1
fi

exit 0
