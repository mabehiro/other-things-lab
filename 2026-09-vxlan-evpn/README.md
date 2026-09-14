# 2026-09 · A small VXLAN/EVPN fabric

One spine, two leaves, two hosts. The hosts share a subnet but have no L2 path
between them, and they ping anyway — the frames ride inside VXLAN and the MACs
are learned over BGP.

Post: **Building a small VXLAN/EVPN fabric in a homelab** — https://otherthings.cloud/posts/vxlan-evpn-homelab-fabric/

```
AS 65000 · VNI 100 (L2) · VXLAN UDP 4789 · underlay 192.168.30.0/24 · tenant 192.168.40.0/24
```

See `topology.txt` for the diagram.

## Files

| Path | What |
|---|---|
| `configs/evpn.clab.yml` | containerlab topology — the whole fabric in one file |
| `configs/frr-spine1.vtysh` | BGP underlay + EVPN address family, route reflector |
| `configs/frr-leaf1.vtysh` | same for leaf1 (leaf2 differs only in router-id) |
| `configs/vxlan-leaf1.sh` | the kernel VXLAN device and bridge — where VNI 100 actually comes from |
| `configs/firewalld.sh` | opens 179/tcp and 4789/udp |
| `configs/99-evpn-unmanaged.conf` | stops NetworkManager reclaiming the leaf's NIC |
| `systemd/evpn-fabric-leaf1.service` | makes the dataplane survive a reboot |

Order: firewall → FRR configs → VXLAN devices → verify → persistence.

## Two ways to run it

**containerlab** is the fast one — `clab deploy -t configs/evpn.clab.yml` and
the whole fabric is up in under a minute. Use it to iterate.

**Five VMs** is what the post measured on. Every number and every capture in
the post came from the VM build; containerlab is included here because it is
the quickest way to stand the topology up and poke at it, not because it is
what was measured.

Tested against FRR **8.4_git** (containerlab, 2026-08-26) and FRR **8.5.3**
(RHEL AppStream, 2026-08-27).

⚠️ `evpn.clab.yml` pins `frrouting/frr:latest`, which resolved to 8.4_git on
2026-08-26. `latest` is not reproducible — pin a digest if you want the same
fabric next month.

## What is not here, and why

**There is no `show run` snapshot.** What `configs/frr-*.vtysh` contains is the
sequence actually typed into vtysh, which *is* the configuration — but it is
not a dump of what FRR reported back afterwards, and I did not take one while
the fabric was L2-only. That state no longer exists: the lab has since been
extended to L3, so a snapshot today would come back carrying a tenant VRF and
a second VNI that this post never covered.

Capturing the running config at experiment time, rather than at write-up time,
is the lesson. Later directories here should have one.

## Two things that cost real time

Both are silent. Neither produces an error naming the cause.

**The systemd ordering cycle.** If you add `Before=frr.service` to the unit,
systemd has a loop — `frr.service` declares `Before=network.target` — and it
breaks a cycle by deleting one job, picking a different victim on each host.
One leaf silently never ran the unit while reporting `enabled`; the other,
from a byte-identical file, was fine. `enabled` is not proof it ran; check
`is-active` and `journalctl -u evpn-fabric -b | grep 'ordering cycle'`.

**NetworkManager taking the NIC back.** It reclaims the host-facing interface
out of the bridge unless the keyfile exclusion is in place, and EVPN stays
perfectly healthy while it happens — the remote MAC is still there via BGP,
the ping just stops. The runtime `nmcli device set ens19 managed no` does not
survive a reboot, which is how one leaf ended up accidentally healthy and
scheduled to fail on its next boot.
