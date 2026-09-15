#!/bin/bash
# leaf2 -- give br100 the tenant gateway address, inside the VRF.
# This is the step that creates the prefix: enslaving br100 to tenant-a puts
# the connected route 192.168.40.0/24 into the VRF's table, and that is what
# gets advertised as Type-5.
#
# The IP *and* the MAC are identical on leaf1 and leaf2 -- that is the point.
# A host must get the same ARP answer whichever leaf it sits behind.
set -eux

# ⚠️ ANYCAST GATEWAY: identical IP *and* identical MAC on BOTH leaves.
ip link set br100 address 02:00:00:40:00:01     # same on leaf1 and leaf2
ip addr add 192.168.40.1/24 dev br100           # same on leaf1 and leaf2
ip link set br100 master tenant-a
