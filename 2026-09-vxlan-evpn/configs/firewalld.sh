#!/bin/bash
# RHEL runs firewalld by default and it blocks both BGP and VXLAN.
# Without this the BGP session never establishes and nothing says why;
# with BGP open but 4789 closed, the session comes up and the ping dies
# silently instead. Debian minimal has no firewall, which is why the
# containerlab build never hit this.
set -eux

firewall-cmd --permanent --add-port=179/tcp --add-port=4789/udp
firewall-cmd --reload
firewall-cmd --list-ports
