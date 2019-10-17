#!/bin/bash
IperfPs=$(ps -o pid,args -ef  | grep "iperf3 -s" | grep -v grep)
if [ ! -z "$IperfPs" ]; then
    IperfPid=$(echo $IperfPs | cut -d' ' -f1)
    IperfCmd=$(echo $IperfPs | cut -d' ' -f2-)
fi

