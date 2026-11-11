#!/bin/sh

BRIDGE_NAME="br0"

case "$1" in
    start|"")
        if [ ! -d /sys/class/net/${BRIDGE_NAME} ]; then
            ip link add name ${BRIDGE_NAME} type bridge
        fi
        ;;
    stop) ;;
    *)
        echo "Usage: $0 {start|stop}" >&2
        exit 1
        ;;
esac