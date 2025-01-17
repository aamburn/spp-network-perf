#!/bin/bash

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
Interactive=
ContainerName=spp-network-perf-runtime

print_usage()
{
    cat <<EOF
USAGE: start-service.sh [-h] [-c command]

  -h  Show help and exit
  -i  Run the container interactively
  -m  Initial PMTU setting in tinc.conf (default: 1514)
  -c  Alternate command to run in the container (-c /bin/bash to get a prompt)
      Always specify the -c option last (most useful with -i)

EOF
    exit 0
}

while getopts ":him:" opt; do
    case $opt in
    h)
        print_usage
        ;;
    i)
        Interactive=true
        shift
        ;;
    m)
        InitialPmtu=$OPTARG
        regex='^[0-9]+$'
        if ! [[ "$InitialPmtu" =~ $regex ]] ; then
            >&2 echo "Non-numeric ID provided '$InitialPmtu'"
            exit 1
        fi
        shift; shift
        ;;
    ?)
        break
        ;;
    esac
done

if test -t 1; then
    YELLOW='\033[1;33m'
    NC='\033[0m'
fi


# Make sure docker is installed
if [ -z "$(which docker)" ]; then
    >&2 echo "You must install docker to use this script"
    exit 1
fi


# Check to see if spp-network-perf-runtime is running
docker ps | grep $ContainerName
if [ $? -eq 0 ]; then
   echo -e "${YELLOW}The container is already running${NC}"
   exit 0
fi


# Gather IP address information (only supports IPv4)
. $ScriptDir/data/scripts/utils.sh
if [ "$(uname)" = "Darwin" ]; then
    IpAddress=$(ifconfig | grep inet | grep -v inet6 | cut -d' ' -f2 | tr '\n' ',')
else
    IpAddress=$(ip -o route get to 8.8.8.8 | sed -n 's/.*src \([0-9.]\+\).*/\1/p' | tr '\n' ',')
fi
IpAddress=${IpAddress%,}
if [ -z "$IpAddress" ]; then
    read -p "Local IP Address: " IpAddress
elif [ $(echo $IpAddress | awk -F',' '{print NF}') -gt 1 ]; then
    read -p "Local IP Address ($IpAddress): " IpAddress
else
    echo "Local IP Address: $IpAddress"
fi
check_ip_address $IpAddress
read -p "Peer IP addresses (comma-delimited): " PeerIpAddresses
for Ip in $(echo $PeerIpAddresses | sed "s/,/ /g"); do
    check_ip_address $Ip
    if [ "$IpAddress" = "$Ip" ]; then
        >&2 echo "Peer IP '$Ip' is the same as local IP '$IpAddress'"
        exit 1
    fi
done


# Build spp-network-perf image if needed
docker images | grep spp-network-perf
if [ $? -ne 0 ]; then
    echo -e "${YELLOW}Building container image${NC}"
    $ScriptDir/build.sh
fi

# Clean up any old container with that name
docker ps -a | grep spp-network-perf-runtime
if [ $? -eq 0 ]; then
    docker rm $ContainerName
fi

# Start the container
if [ ! -z "$Interactive" ]; then
    echo -e "${YELLOW}Running interactive container with IP Address: $IpAddress and Peer IP Addresses: $PeerIpAddresses${NC}"
    DockerArg=-it
else
    echo -e "${YELLOW}Running background container with IP Address: $IpAddress and Peer IP Addresses: $PeerIpAddresses${NC}"
    DockerArg=-dit
fi
docker run \
    --name $ContainerName \
    -p $IpAddress:8080:8080 -p $IpAddress:655:655 -p $IpAddress:655:655/udp \
    --env-file <(echo "LOCAL_IP=$IpAddress"; echo "PEER_IPS=$PeerIpAddresses"; echo "PMTU=$InitialPmtu") \
    --cap-add NET_ADMIN \
    --sysctl net.ipv6.conf.all.disable_ipv6=0 \
    $DockerArg spp-network-perf "$@"

