# Reach a Device From a Namespace

Beamline devices — motor controllers, serial-to-ethernet boxes, detectors —
live on networks that are routed from the cluster nodes, and normally from
pods too. When an IOC cannot talk to its hardware, the question is which of
three quite different things has gone wrong.

This is the one thing `ec-netshoot` can do that nothing else can.

## The A/B test

Run the same probe twice on the **same node**, once through the pod network and
once through the node's:

```bash
netshoot -n i07-beamline --node bl07i-node1 \
    -c 'nc -zv moxa1.diamond.ac.uk 4001'

netshoot -n i07-beamline --node bl07i-node1 --host-network \
    -c 'nc -zv moxa1.diamond.ac.uk 4001'
```

Two results, three conclusions:

| Pod network | Host network | What it means |
|---|---|---|
| works | works | Not a network problem. Look at the IOC. |
| fails | works | The **cluster** is in the way — see below. |
| fails | fails | The device is down, or this node has no path to it at all. |

Your workstation cannot give you this. It sits on a third network, so a
successful probe from your desk proves nothing about what a pod on that node
sees, and neither does a failed one.

## "Fails in pod, works on host"

With egress otherwise open, the usual culprit is **masquerade**.

A CNI normally SNATs pod traffic leaving the cluster CIDR, so the device sees
the node's address and replies to the node. If the device subnet sits on the
CNI's masquerade *exclusion* list — a common configuration, since private
ranges are often excluded — the SYN leaves with a pod-CIDR source address, the
device has no route back, and nothing returns.

The symptom is a **one-way blackhole**: the packet definitely left, nothing
ever comes back, and it is indistinguishable from "the device is off" unless
you do the A/B or capture at the far end.

Confirm it by watching where the path stops:

```bash
tracepath moxa1.diamond.ac.uk
```

Other candidates, in rough order of likelihood: a NetworkPolicy with an egress
rule; the device subnet missing from the cluster's route table; the device
itself having no return route to the pod CIDR.

## Devices attached to one specific node

Some devices are wired to a particular node — USB, or a NIC dedicated to a
detector. For those, "am I even on a node that can see this?" is the *first*
question, not a later one. `--node` pins the pod:

```bash
netshoot -n i07-beamline --node bl07i-node1
```

`--node` sets `nodeName`, which bypasses the scheduler. That is deliberate:
beamline nodes are frequently tainted, and a `nodeSelector` would leave you
staring at a `Pending` pod. The tradeoff is that it also bypasses capacity
checks, so a full node rejects the pod with `OutOfcpu` rather than pending
politely.

## USB devices

DLS nodes honour a `usb-compat` annotation which mounts the whole of
`/dev/bus/usb` into the container:

```bash
netshoot -n i07-beamline --node bl07i-node1 --annotation usb-compat=enabled
```

Then:

```bash
lsusb                 # what the node actually sees
lsusb -v -d 1234:5678 # detail for one device
ls -l /dev/bus/usb/*/*
```

The reason it mounts the entire bus tree rather than a single device node is
that poorly-behaved USB devices **re-enumerate onto a new bus address when they
initialise**. A container holding a single device node loses it the moment the
device resets; one holding the whole tree does not.

The annotation is a node-side capability rather than anything in this image, so other
facilities can implement the same annotation and use the same command.

## Do not scan device networks

`nmap` is deliberately **not** in this image. Serial-to-ethernet boxes, older
motor controllers and PLCs have thin TCP stacks that can wedge, drop their one
allowed connection, or stop answering entirely when scanned — turning a network
question into a hardware power-cycle.

You almost always know the address and port already, and where you do not,
`nc` takes a range:

```bash
nc -zv moxa1.diamond.ac.uk 4000-4010
```
