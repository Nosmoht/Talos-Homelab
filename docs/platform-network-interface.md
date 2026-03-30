# Platform Network Interface (PNI) - Consumer Guide

## Purpose

Platform Network Interface (PNI) is the standard way to consume cluster-managed platform services without writing custom network policies per deployment.

If your workload opts in to PNI correctly, required Cilium policies are handled by the platform.

If your workload does not use PNI, you must provide and operate your own network policies and you may not be able to use managed capabilities.

## Audience

- Application teams deploying workloads into the cluster
- Platform consumers using managed services (for example Redis, Kafka, PostgreSQL, Vault, monitoring)

## What PNI Solves

- No per-team per-namespace CNP authoring for common platform integrations
- Consistent least-privilege network behavior across teams
- Faster onboarding to platform services via explicit capability opt-in
- Safer multi-tenant boundaries by default

## Core Concepts

### Provider

A platform-managed component exposing one or more capabilities (for example Strimzi, CNPG, Vault, Prometheus).

### Consumer

A tenant namespace and its workloads that opt in to one or more capabilities.

### Capability

A named function offered by the platform and backed by pre-defined network policy rules.

Examples:

- `monitoring-scrape`
- `vault-secrets`
- `cnpg-postgres`
- `redis-managed`
- `kafka-managed`
- `s3-object`
- `gateway-backend`
- `tls-issuance`
- `storage-csi`
- `gpu-runtime`
- `logging-ship`
- `hpa-metrics`

### Network Profile

A coarse baseline behavior for a namespace:

- `restricted`: minimal baseline, capability access only via explicit opt-in
- `managed`: platform-managed baseline for typical app namespaces
- `privileged`: exception profile, only by platform approval

`network-profile` alone is not enough to access core services. Capability opt-in is required.

## PNI Contract (v1)

### Required Namespace Labels

```yaml
metadata:
  labels:
    platform.io/network-interface-version: "v1"
    platform.io/network-profile: "managed"
```

### Capability Opt-In Labels

Set capability labels on the namespace (recommended default) or explicitly documented workload-level metadata:

```yaml
metadata:
  labels:
    platform.io/consume.monitoring-scrape: "true"
    platform.io/consume.vault-secrets: "true"
    platform.io/consume.cnpg-postgres: "true"
```

### Reserved Labels (Platform-Owned)

The following labels are provider-owned and must not be set by consumer teams:

- `platform.io/provider`
- `platform.io/managed-by`
- `platform.io/capability`

Admission policy (Kyverno) enforces this separation.

## Capability Catalog (Current Cluster)

| Capability | Provider Components | Typical Consumer Use |
|---|---|---|
| `monitoring-scrape` | `kube-prometheus-stack`, `vault-config-operator` | Prometheus metrics scraping |
| `logging-ship` | `alloy`, `loki` | Log forwarding and ingestion |
| `vault-secrets` | `vault-operator`, `vault-config-operator`, `external-secrets` | Secret and PKI integration |
| `cnpg-postgres` | `cloudnative-pg` | Managed PostgreSQL workloads |
| `redis-managed` | `redis-operator` | Managed Redis instances |
| `kafka-managed` | `strimzi-kafka-operator` | Managed Kafka clusters/topics |
| `s3-object` | `minio-operator`, `minio` | S3-compatible object storage |
| `storage-csi` | `piraeus-operator` | Persistent volumes via CSI |
| `tls-issuance` | `cert-manager`, `cert-approver` | Certificate issuance and renewal |
| `gateway-backend` | `gateway-api` (Cilium dataplane) | Backend exposure via Gateway API |
| `gpu-runtime` | `nvidia-device-plugin`, `nvidia-dcgm-exporter`, `node-feature-discovery` | GPU workload scheduling and telemetry |
| `hpa-metrics` | `metrics-server` | Resource metrics for autoscaling |
| `internet-egress` | `cilium` | Egress to public internet (all ports) |

## Onboarding Workflow (Consumer)

1. Choose a namespace network profile (`restricted` or `managed`).
2. Set `platform.io/network-interface-version: v1`.
3. Opt in only to required capabilities using `platform.io/consume.<capability>: "true"`.
4. Deploy your workloads or custom resources.
5. Consumer egress is automatically granted by PNI consumer CCNPs once the capability label is set.
6. Validate connectivity and policy behavior.

## Current Policy Coverage (Core Platform)

The following core flows are currently implemented through platform-owned PNI policies:

- Monitoring DNS visibility: `monitoring` -> `kube-dns` (`53/TCP,UDP`)
- Monitoring scrape to Vault Config Operator metrics: `prometheus` -> `vault-config-operator` (`8443/TCP`)
- Monitoring scrape to External Secrets metrics: `prometheus` -> `external-secrets`, `external-secrets-webhook`, `external-secrets-cert-controller` (`8080/TCP`)
- Redis operator control-plane baseline: `redis-operator` -> API server + DNS
- Redis operator data-plane access: `redis-operator` -> managed Redis pods (`6379/TCP`, `26379/TCP`)
- Strimzi operator control-plane baseline: `strimzi-cluster-operator` -> API server + DNS
- Strimzi operator data-plane access: `strimzi-cluster-operator` -> managed Kafka pods (`9090/TCP`, `9091/TCP`, `9092/TCP`)
- Vault operator control-plane baseline: `vault-operator` -> API server + DNS
- External Secrets operator control-plane baseline: `external-secrets` -> API server + DNS
- CNPG operator control-plane baseline: `cloudnative-pg` -> API server + DNS + managed CNPG pods (`5432/TCP`, `8000/TCP`)
- Vault CA distribution for consumers: `cert-manager/vault-ca` -> namespaces labeled `platform.io/network-interface-version=v1` and `platform.io/consume.vault-secrets=true`
- MinIO operator control-plane baseline: `minio-operator` -> API server + DNS
- Piraeus operator control-plane baseline: `piraeus-operator` -> API server + DNS

### Consumer Capability Policies

Consumer-side policies grant network access for any namespace that opts in to a capability.
Selection is by namespace labels (`k8s:io.cilium.k8s.namespace.labels.*`), not by pod or deployment names.
All pods in the opted-in namespace receive the grant.

Most consumer CCNPs are **egress** grants (consumer -> provider). The `gateway-backend` capability is an **ingress** grant (gateway proxy -> consumer backend pods). In both cases, per-service CNPs on the provider/consumer side remain the fine-grained authorization boundary.

#### Egress (consumer -> provider)

- S3 object storage: namespaces with `consume.s3-object=true` -> MinIO tenant pods (`9000/TCP`) + MinIO Operator STS (`4223/TCP`) + DNS
- CNPG PostgreSQL: namespaces with `consume.cnpg-postgres=true` -> CNPG cluster pods (`5432/TCP`) + DNS
- Vault secrets: namespaces with `consume.vault-secrets=true` -> Vault pods (`8200/TCP`) + DNS
- Redis managed: namespaces with `consume.redis-managed=true` -> Redis pods (`6379/TCP`) + DNS
- Kafka managed: namespaces with `consume.kafka-managed=true` -> Kafka broker pods (`9092/TCP`) + DNS
- Internet egress: namespaces with `consume.internet-egress=true` -> public internet via `toCIDRSet 0.0.0.0/0` excluding RFC1918 (all ports/protocols) + DNS

#### Ingress (gateway proxy -> consumer)

- Gateway backend: namespaces with `consume.gateway-backend=true` receive ingress from Cilium Gateway API proxy (`reserved:ingress` identity) on container ports `3000/TCP`, `4180/TCP`, `5556/TCP`, `8200/TCP`

Ports in the gateway-backend CCNP are **container/pod ports** (post-DNAT), not Service ports — Cilium `toPorts` evaluates after kube-proxy DNAT. When adding a new gateway-exposed backend, add its container port to the CCNP.

Namespaces without existing CiliumNetworkPolicies (e.g. `argocd` with `privileged` profile) should **not** opt in to `gateway-backend` or `internet-egress` — the CCNP would be the first policy selecting their pods, activating Cilium's implicit default-deny and breaking intra-namespace communication. Gateway traffic already works in those namespaces since no default-deny is active.

#### API-only capabilities (no CCNP)

The following capabilities are valid opt-in labels but do not require consumer network policies.
Interaction with the provider happens through the Kubernetes API, CRDs, or node-level mechanisms — not pod-to-pod networking.

| Capability | Interaction Model |
|---|---|
| `logging-ship` | Alloy DaemonSet collects container logs from the node filesystem; consumer pods write to stdout/stderr |
| `storage-csi` | CSI volumes provisioned via Kubernetes API; kubelet handles block device attachment at node level |
| `tls-issuance` | Certificates managed via `Certificate` CRDs; cert-manager controller watches the API, no direct network path |
| `gpu-runtime` | NVIDIA device plugin exposes GPUs via kubelet device plugin socket; node-local only |
| `hpa-metrics` | Metrics Server aggregated into Kubernetes API (`metrics.k8s.io`); HPA controller queries via kube-apiserver |

The `monitoring-scrape` capability has a CCNP but follows a different pattern: it is a **provider-egress** grant (Prometheus scrapes into consumer namespaces), not a consumer-egress grant like the other 7 CCNPs.

These labels still require `platform.io/consume.<capability>` on the namespace for audit visibility, Kyverno validation, and forward compatibility with future policy changes.

Implementation rules:

- Policies are platform-owned and reusable.
- Operator control-plane baselines (including `external-secrets`) are implemented as platform-owned `CiliumClusterwideNetworkPolicy` resources under PNI.
- Selectors should be provider/generic label-based.
- Do not encode consumer deployment names or tenant-specific namespace names in PNI policies.
- Consumer capability egress policies use `k8s:io.cilium.k8s.namespace.labels.*` selectors to match all pods in opted-in namespaces -- no hardcoded namespace or pod names on the consumer side.

## Minimal Example

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: team-a
  labels:
    platform.io/network-interface-version: "v1"
    platform.io/network-profile: "managed"
    platform.io/consume.monitoring-scrape: "true"
    platform.io/consume.vault-secrets: "true"
    platform.io/consume.redis-managed: "true"
```

## Validation Checklist (Consumer)

1. Render:
   - `kubectl kustomize kubernetes/overlays/homelab`
2. Dry-run:
   - `kubectl apply -k kubernetes/overlays/homelab --dry-run=client`
3. Runtime:
   - confirm app readiness and successful provider interactions
   - verify expected flows with Hubble where needed

## What Happens If You Do Not Use PNI

- No automatic capability allow-rules
- You must ship your own CNP/KNP for required connectivity
- Platform support may require reproducing the issue with PNI-compliant metadata first

## Security Model

- Default posture is deny-by-default once policies select endpoints.
- Capability access is granted only through explicit opt-in metadata.
- Provider-side identities and grants are platform-owned.
- Cross-tenant communication is denied unless explicitly allowed.

## Troubleshooting

1. Capability not working:
   - verify exact capability label key and value (`"true"`)
   - verify namespace has `platform.io/network-interface-version: v1`
2. Traffic blocked:
   - inspect Hubble drops and effective identities
   - check whether workload is using unsupported ports/protocols for that capability
3. Admission denied:
   - confirm you are not setting provider-reserved labels
4. Unknown capability warning:
   - check for typos in `platform.io/consume.*` labels (e.g., `internet-igress` instead of `internet-egress`)
   - Kyverno audits unknown capability labels and emits warnings

## FAQ

### Is `platform.io/network-profile` enough by itself?

No. Profile defines baseline posture. Core platform access requires explicit `platform.io/consume.<capability>` labels.

### Can I opt in only for monitoring and Vault?

Yes. Opt in to exactly the capabilities you need.

### Can I bypass PNI?

Yes, with self-managed policies. You then own policy design, testing, and incident handling for that traffic path.

## Versioning and Compatibility

- Current contract: `v1`
- Future versions may introduce new capabilities or stricter validation
- Consumers should pin `platform.io/network-interface-version` explicitly
