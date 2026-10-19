#!/bin/bash
# Gives spine1 an address on the nodes' primary network (VLAN 20), so the nodes
# can peer with it over br-ex. Run on spine1. A delta: spine1 already exists
# from the earlier posts.
#
# never-default: spine1 keeps its default route on VLAN 30. This NIC only adds
# 192.168.20.0/24 as a connected network.
#
# ens19 was the name of the new NIC on spine1. Check yours with `ip -br link`.
#
# Side effect: with strict rp_filter on spine1, VLAN 20 hosts that reach
# spine1's VLAN 30 address through a router are dropped. That's spine1's
# setting, not the cluster's.
set -eux

nmcli con add type ethernet ifname ens19 con-name vlan20 \
  ipv4.method manual ipv4.addresses 192.168.20.25/24 \
  ipv4.never-default yes ipv6.method disabled
nmcli con up vlan20

# Then add the listen range in vtysh (see frr-spine1-running.conf):
#   conf t
#   router bgp 65000
#    bgp listen range 192.168.20.48/29 peer-group nooverlay
#   end
#   write memory
