#!/bin/bash
# host-a and host-b have no default route by design -- in the L2 fabric they
# only ever talked to each other. Without this they cannot send anything
# off-subnet even once the SVI exists.
# Persist via nmcli, or it is lost on reboot like everything else here.
set -eux

# ON host-a and host-b
ip route add default via 192.168.40.1
