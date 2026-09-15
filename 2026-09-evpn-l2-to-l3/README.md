# 2026-09 · Extending the EVPN fabric from L2 to L3

The fabric from the previous experiment carried two hosts on one subnet across
two leaves. This adds the routing half: a tenant VRF, an L3 VNI, and an anycast
gateway on the bridge that was already there — so the subnet can be advertised
as a prefix rather than only as MAC addresses.

Post: **Extending an EVPN fabric from L2 to L3** — https://otherthings.cloud/posts/extending-evpn-fabric-l2-to-l3/

```
AS 65000 · VNI 100 (L2) · VNI 101 (L3) · VRF tenant-a
tenant 192.168.40.0/24 · anycast gateway 192.168.40.1 · underlay 192.168.30.0/24
```

See `topology.txt`.

## ⚠️ This builds on the previous experiment

**Not standalone.** Apply [`../2026-09-vxlan-evpn/`](../2026-09-vxlan-evpn/) first —
the underlay, BGP, VNI 100 and the L2 dataplane all come from there. What is here
is only what the L2→L3 step adds.

The two exceptions are whole-file artifacts, which are shipped complete rather
than as fragments because they have to exist whole on the machine:

- `systemd/evpn-fabric-leafN.service` — the **complete** unit, L2 devices and L3
  devices together. It replaces the L2-only version from the previous directory.
- `configs/99-evpn-unmanaged.conf` — **replaces** the L2 version, which listed
  `ens19` only.

## Files

| Path | What |
|---|---|
| `configs/frr-l3-vrf.vtysh` | the `vrf tenant-a` / `vni 101` binding and `router bgp … vrf tenant-a` |
| `configs/host-default-route.sh` | `host-a` and `host-b` finally get a default route |
| `configs/99-evpn-unmanaged.conf` | NetworkManager exclusion, now four interfaces |
| `systemd/evpn-fabric-leaf1.service` | complete unit — recreates all five devices **and the anycast SVI** at boot |

Order: FRR VRF block → `systemctl start evpn-fabric` → host default routes.

The unit does the whole dataplane, including giving `br100` its gateway address
and enslaving it to the VRF. Those three commands are kernel state exactly like
the device creation, so keeping them anywhere else means a rebooted leaf comes
back with the L2 fabric working, no gateway, no connected route in the VRF, and
no Type-5 originated — with nothing reporting an error.

## The one that is easy to miss

`advertise ipv4 unicast` is necessary but not sufficient. It exports what is in
**BGP's** IPv4 table for the VRF, and a connected route lives in the **kernel's**
table until something puts it into BGP. Without `redistribute connected` no Type-5
route is ever originated — and nothing reports an error. `show evpn vni` is
correct, `ip route show vrf tenant-a` shows the `/24`, the config looks right.

Both lines are in `configs/frr-l3-vrf.vtysh`.

## The anycast gateway is anycast on purpose

`192.168.40.1` and MAC `02:00:00:40:00:01` are identical on both leaves. A host
must get the same ARP answer whichever leaf it sits behind; otherwise traffic
follows a MAC that lives on the wrong VTEP. Setting the bridge MAC explicitly
also pins it — Linux otherwise derives a bridge's MAC from its members and it
can change underneath you.

That is the reasoning for doing it. It was not tested by setting the leaves
differently and watching it break.

## What is not here, and why

**There is no `show run` snapshot and no `systemctl cat` output.** The FRR block
and the systemd units are the configuration as applied, not as read back off the
machine. Neither `vtysh -c 'show run'` nor `systemctl cat evpn-fabric` has been
captured.

Unlike the L2-only fabric in the previous directory — which no longer exists and
can never be snapshotted — **this state is live**, so both captures are still
possible. They belong here when taken.

## Versions

FRR **8.5.3** (RHEL AppStream), five RHEL VMs on one Proxmox host. Symmetric IRB;
asymmetric IRB is not supported on the OpenShift side, which is where this is
heading next.
