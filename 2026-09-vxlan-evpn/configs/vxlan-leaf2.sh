#!/bin/bash
# leaf2 -- the VXLAN dataplane. THIS is where VNI 100 comes from; there is no
# 'vni 100' line in the FRR config. zebra discovers this over netlink.
#
# ens19 is the host-facing NIC (toward host-b). Adjust for your hardware.
# MTU 1450 = 1500 underlay - 50 bytes of VXLAN encapsulation.
#
# NOT persistent -- 'write memory' does not save any of this, it is kernel
# state rather than FRR config. See ../systemd/evpn-fabric-leaf2.service.
set -eux

UP=ens19

ip link add vxlan100 type vxlan id 100 dstport 4789 local 192.168.30.12 nolearning
ip link add br100 type bridge
ip link set vxlan100 master br100
ip link set $UP      master br100
ip link set vxlan100 mtu 1450
ip link set br100    mtu 1450
ip link set $UP      mtu 1450
ip link set vxlan100 up
ip link set br100    up
ip link set $UP      up
