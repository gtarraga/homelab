# ADR 001: Tailscale subnet routes for pod CIDRs

**Date:** 2026-06-30  
**Status:** Accepted

## Context

K3s nodes use Tailscale IPs (`100.x`) as node addresses. Cross-node pod traffic relies on Flannel VXLAN, but VXLAN over Tailscale is fragile (MTU, UDP encapsulation overhead). Pods on cradle (`10.42.3.0/24`) could not reach pods on jitte (`10.42.0.0/24`), breaking CoreDNS and HelmRelease chart fetches.

## Decision

Advertise pod CIDRs as Tailscale subnet routes on each node:

| Node | Advertised routes |
|------|-------------------|
| jitte | `192.168.1.0/24`, `10.42.0.0/24` |
| cradle | `10.42.3.0/24` |

Both nodes accept routes (`--accept-routes`). This provides a reliable path for cross-node pod traffic over Tailscale, bypassing broken VXLAN.

## Consequences

- **Positive:** Pods on different nodes can communicate reliably via Tailscale routes
- **Positive:** No dependency on Flannel VXLAN health for cross-node traffic
- **Neutral:** Adding/changing node pod CIDRs requires updating advertised routes
- **Negative:** Cross-node pod traffic routes through Tailscale DERP relays if direct P2P fails (latency increase, but rare on this homelab LAN)
