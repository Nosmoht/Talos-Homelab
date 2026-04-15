# gateway-api (homelab overlay)

Resources for the shared `homelab-gateway` Cilium Gateway, including TLS
certificates and HTTPRoutes managed alongside the Gateway itself.

## Listeners

| Listener | Hostname | TLS Cert | allowedRoutes |
|---|---|---|---|
| `http` | (any) | — | `from: Same` (only the gateway namespace) |
| `https` | (any) | `homelab-wildcard-tls` (Vault internal CA) | `from: All` namespaces |
| `external-https` | `*.homelab.ntbc.io` | `external-wildcard-tls` (Let's Encrypt) | `from: Selector` matching `platform.io/consume.external-gateway-routes=true` |

A single Envoy serves all three listeners. SNI dispatch on `external-https` is
hostname-bound to `*.homelab.ntbc.io`; the listener attaches only HTTPRoutes from
namespaces that carry the `consume.external-gateway-routes` opt-in label.

## Public exposure path

```
Internet (TCP 443 only)
  -> Router public IP (port-forward)
  -> ingress-front macvlan VIP (LAN)
  -> nginx stream proxy
  -> gateway nodes (hostNetwork Envoy)
  -> external-https listener (SNI = *.homelab.ntbc.io)
  -> HTTPRoutes from labelled namespaces
```

Port `80` is intentionally NOT forwarded from the WAN. Let's Encrypt issuance uses
DNS-01 (CloudDNS), not HTTP-01, so port 80 is unnecessary. Public clients must use
HTTPS only.

## Reviewer checklist for new external HTTPRoutes

Before approving any HTTPRoute that targets the `external-https` listener:

- [ ] Consumer namespace carries `platform.io/consume.external-gateway-routes: "true"`
- [ ] HTTPRoute `parentRefs[].sectionName: external-https`
- [ ] Hostname matches `*.homelab.ntbc.io` (no apex-bare hostname leaks)
- [ ] **Authentication is enforced at the application layer** (Dex/OIDC,
      oauth2-proxy, mTLS, signed cookies, etc.). SNI isolation does NOT
      authenticate clients — anyone on the public internet can reach the route.
- [ ] Service has its own CNP (do NOT rely on the public listener for
      authorization)
- [ ] PR description includes a curl-from-WAN verification log proving the route
      serves the expected response and that internal hostnames return 404 from
      the public IP

## Related

- Gateway resource: `resources/gateway.yaml`
- External wildcard cert: `resources/certificate-external.yaml` (Let's Encrypt)
- Internal wildcard cert: `resources/certificate.yaml` (Vault internal CA)
- PNI capability: `external-gateway-routes` (registered in
  `kubernetes/base/infrastructure/platform-network-interface/resources/capability-registry-configmap.yaml`)
- Reference: `docs/platform-network-interface.md`
