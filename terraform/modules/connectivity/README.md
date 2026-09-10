# Platform connectivity

This composition is part of the platform landing zone. It owns Azure network
connectivity for the shared platform and future application landing zones. The
AVM ALZ connectivity pattern is used for shared hub capabilities: hub VNet,
hub subnets, hub routing, Bastion, private DNS, and capability-gated egress
services.

The ingress/platform-services VNet and each application landing-zone VNet are
separate AVM VNet resource-module compositions. They are explicitly peered to
the platform hub and remain independently owned so future applications can
have separate address spaces and lifecycles. The selected connectivity
pattern's `hub_virtual_networks` input is not a substitute for those spoke VNet
compositions.

This module does not implement application ingress. External application
traffic remains subject to the tunnel-enforced private ingress contract:

```text
Cloudflare Tunnel -> APISIX -> private workload upstream
```

No workload composition should add a public application endpoint or bypass this
chain.
