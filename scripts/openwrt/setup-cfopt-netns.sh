#!/bin/sh
set -eu

NAMESPACE="${CFOPT_NETNS:-cfopt}"
INTERFACE="${CFOPT_NETNS_INTERFACE:-cfopt0}"
PARENT_INTERFACE="${CFOPT_PARENT_INTERFACE:-br-lan}"
ADDRESS="${CFOPT_NETNS_ADDRESS:-192.168.0.3/24}"
GATEWAY="${CFOPT_DIRECT_GATEWAY:-192.168.0.1}"
RESOLV_SOURCE="${CFOPT_RESOLV_SOURCE:-/etc/cfopt/resolv.conf}"

ip netns delete "$NAMESPACE" 2>/dev/null || true
ip link delete "$INTERFACE" 2>/dev/null || true

ip netns add "$NAMESPACE"
ip link add "$INTERFACE" link "$PARENT_INTERFACE" type macvlan mode bridge
ip link set "$INTERFACE" netns "$NAMESPACE"
ip -n "$NAMESPACE" link set lo up
ip -n "$NAMESPACE" address add "$ADDRESS" dev "$INTERFACE"
ip -n "$NAMESPACE" link set "$INTERFACE" up
ip -n "$NAMESPACE" route add default via "$GATEWAY"

mkdir -p "/etc/netns/$NAMESPACE"
cp "$RESOLV_SOURCE" "/etc/netns/$NAMESPACE/resolv.conf"
