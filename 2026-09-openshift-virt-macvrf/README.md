# 2026-09 · Live-migrating a VM across an EVPN fabric

A VM on OpenShift Virtualization, on a Layer2 EVPN network that shares a
subnet and a MAC-VRF with two plain hosts behind the fabric's leaves. It
live-migrates between nodes and keeps its IP and MAC; the fabric sees an EVPN
MAC move.

Post: **Live-migrating a VM across an EVPN fabric** — https://otherthings.cloud/posts/live-migrating-a-vm-across-an-evpn-fabric/

```
MAC-VRF VNI 100 / RT 65000:100 · 192.168.40.0/24 · no IP-VRF
host-a .10 (leaf1) · host-b .11 (leaf2) · VMs from .32
```

See `topology.txt`.

## ⚠️ This needs the fabric and the cluster join first

**Not standalone.** Everything here is a delta on top of:

1. [`../2026-09-vxlan-evpn/`](../2026-09-vxlan-evpn/) — the L2 fabric, which already bridges VNI 100
2. [`../2026-09-evpn-l2-to-l3/`](../2026-09-evpn-l2-to-l3/) — the anycast gateway `192.168.40.1`
3. [`../2026-09-openshift-evpn/`](../2026-09-openshift-evpn/) — FRR-K8s, the `VTEP` CR `evpn-vtep`, and the `FRRConfiguration` `evpn-fabric-peering`, all reused here

The leaves need no change. They already bridge VNI 100.

OpenShift Virtualization must be installed, with an RWX storage class for the
VM's disk.

## Apply in order

| File | What |
|---|---|
| `manifests/01-namespace.yaml` | both labels must be present **at creation** |
| `manifests/02-cudn.yaml` | the Layer2 EVPN network. `spec` is immutable: read it before applying |
| `manifests/03-routeadvertisements.yaml` | required even with nothing to route |
| `manifests/04-vm.yaml` | set the password and storage class first |

Read the RouteAdvertisements status first, then the network's conditions.
Until the RouteAdvertisements exists, `TransportAccepted` reads `False`, and
that is expected.

```bash
oc get ra advertise-vm-a -o jsonpath='{.status.status}{"\n"}'
oc get clusteruserdefinednetworks.k8s.ovn.org cudn-vm-a \
  -o jsonpath='{.status.conditions}' | python3 -m json.tool
oc get vmi -n vm-a -o wide        # LIVE-MIGRATABLE should read True
```

## Two things to plan before applying

**The gateway.** `defaultGatewayIPs` is set to the fabric's anycast gateway,
`192.168.40.1`, as it was when measured. OVN-Kubernetes then answers ARP for
`.1` too, with its own MAC, so the segment has two MACs for one IP. For a new
build, give the network its own gateway address.

**Other advertised networks.** User-defined networks are isolated from each
other. While `cudn-vm-a` exists, pods on `cudn-tenant-a` (from
`2026-09-openshift-evpn`) cannot reach `host-a` or `host-b`, because those
addresses fall inside `cudn-vm-a`'s subnet. The two experiments cannot run at
the same time.

## Watching a migration

Start all four before migrating. Each runs where its first column says.

| Where | Command | Shows |
|---|---|---|
| `host-b` | `ping -D -O -i 0.2 192.168.40.32 \| tee -i ~/migrate-ping.txt` | lost probes, timestamped. `tee -i` keeps the summary line on Ctrl-C |
| `leaf2` | `tcpdump -ni ens18 'udp port 4789 and host 192.168.30.12' -v` | the outer destination switching between node VTEPs |
| workstation | `oc get vmim -n vm-a -w` | migration phases |
| `spine1` | `watch -n1 "vtysh -c 'show bgp l2vpn evpn route type macip' \| grep -i -A3 0a:58:c0:a8:28:20"` | the Type-2 next hop and the `MM:` sequence number |

```bash
virtctl migrate vm-a1 -n vm-a
```

The MAC above is the one OVN-Kubernetes derives from `192.168.40.32`. Read
yours from `oc get vmi vm-a1 -n vm-a -o jsonpath='{.status.interfaces[0].mac}'`.

In a capture filter, `host` matches the **outer** header. The VM's address
never appears there, so filter on VTEP addresses.

Afterwards, the phase timestamps, with the name `oc get vmim` printed:

```bash
oc get vmim <name> -n vm-a -o jsonpath='{range.status.phaseTransitionTimestamps[*]}{.phase}{"\t"}{.phaseTransitionTimestamp}{"\n"}{end}'
```

And on leaf2, `Remote Seq` should have gone up by one:

```bash
vtysh -c 'show evpn mac vni 100 mac 0a:58:c0:a8:28:20'
```

## Versions

OpenShift **4.22.11**, OpenShift Virtualization **4.22.9**. FRR **8.5.3** on
the fabric side. CentOS Stream 9 guest. Every node, fabric and cluster, is a VM
on one Proxmox host.
