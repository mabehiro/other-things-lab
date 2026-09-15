# other-things-lab

Supporting lab artifacts for experiments written up at
[otherthings.cloud](https://otherthings.cloud) — configurations, manifests,
scripts and topologies.

## What is here, and what is not

This repo holds **artifacts**: the things you would run.

The blog holds the **narrative and the evidence** — what I tried, what
happened, what I got wrong, the measurements and the packet captures. If you
want to know why something is configured the way it is, or whether it actually
worked, that is on the blog. If you want to reproduce it, it is here.

## Layout

One directory per experiment, named `YYYY-MM-<topic>`:

```
other-things-lab/
├── 2026-09-vxlan-evpn/
│   ├── README.md
│   ├── configs/
│   ├── systemd/
│   └── topology.txt
└── ...
```

## The rule that matters

**Each directory is frozen at the state used for its post.** It is not a
mirror of my current homelab, and it does not get updated when the lab moves
on.

This matters more than it sounds. The fabric in `2026-09-vxlan-evpn/` was
extended from L2 to L3 within a few weeks of that post going up. Had these
files tracked the live lab, they would now describe something the post never
tested — and anyone following along would be debugging a mismatch that was my
fault, not theirs.

So older experiments are left alone. If a later experiment changes something,
it gets its own directory.

## Use it however you like

Apache-2.0 — see [LICENSE](LICENSE). Copy it, adapt it, build on it. No
attribution beyond what the licence already asks for.

These are lab configs. They ran on my hardware, against the versions noted in
each experiment's README, and they carry no warranty of any kind. Read them
before you run them.
