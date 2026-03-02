# Network Policy Remediation TODO (homelab)

Date: 2026-03-02
Scope: CiliumNetworkPolicy resources in `monitoring` and `dex` plus uncovered high-value workloads.

- [x] Build runtime inventory of CNPs, selected pods, and recent connectivity failures.
- [x] Fix `prometheus` CNP to allow Kubernetes API egress required for service discovery (`10.96.0.1:443`, `kube-apiserver:443/6443`).
- [ ] Fix `loki` CNP to allow Kubernetes API egress for `loki-sc-rules` sidecar.
- [ ] Fix `loki` CNP to allow Loki canary <-> Loki gateway connectivity on TCP/80.
- [ ] Fix `loki` CNP to allow Loki single-binary <-> Loki memcached caches on TCP/11211.
- [ ] Add missing CNP for `monitoring-prometheus-node-exporter` (currently uncovered in `monitoring` namespace) with least-privilege ingress from Prometheus only.
- [ ] Re-verify runtime after changes: no active API timeout errors in policy-controlled observability components; Grafana/Thanos queries return data.

## Notes
- Prometheus data-path recovery has already been observed (`sum(up)=17` via Thanos from Grafana pod) after the Prometheus CNP fix.
- Remaining open items focus on Loki component-specific traffic and node-exporter hardening.
