# Proxmox Datacenter Manager Containerization Audit and Hardening Roadmap

**Repository:** `willmortimer/proxmox-datacenter-manager-docker`  
**Audit date:** 2026-07-12  
**Status:** Active remediation plan — P0 items (upstream setup, secure compose, volume paths, documentation sync) have landed on `master`.

## Purpose and project position

This repository exists to make Proxmox Datacenter Manager (PDM) easier to evaluate and to support experimental containerized deployments where the official ISO or a conventional Debian VM is not desirable.

The official PDM ISO remains the upstream-preferred installation method, and a normal Debian installation remains closer to the supported system architecture than Docker. That does **not** make this repository unnecessary. The purpose of this project is to produce the safest, most predictable, and most transparent Docker and LXC deployments that can reasonably be built around PDM.

The intended positioning is:

1. **Official PDM ISO** — preferred for conventional production deployments.
2. **Debian VM using official PDM packages** — preferred when infrastructure automation or an existing Debian lifecycle is required.
3. **Unprivileged LXC** — the preferred containerized pathway in this repository because it retains systemd, native package lifecycle behavior, normal service supervision, and Proxmox guest backup/HA integration.
4. **Docker** — an explicitly experimental pathway for evaluation, homelab use, integration testing, and nonstandard environments.

The Docker pathway should not pretend to be an upstream-supported installation method. It should instead make its deviations explicit and compensate with reproducible builds, strong CI, runtime hardening, immutable releases, documented backup procedures, and automated smoke testing.

## Executive summary

The current repository has a solid proof-of-concept foundation but contains several release, packaging, runtime, and documentation defects that prevent it from being treated as a dependable deployment artifact.

The highest-priority issues are:

- The release workflow watches `main`, while the repository default branch is `master`.
- The workflow publishes to a different GHCR path than the README and Compose file consume.
- The documented target is PDM 1.0 while current PDM releases are in the 1.1 series.
- The APT repository and key configuration use an obsolete layout.
- The Docker entrypoint waits for an outdated privileged API socket path.
- ARM64 support is advertised without demonstrated upstream package support.
- VPN-related privileges are granted even when VPN support is disabled.
- Port 8443 is exposed on every host interface by default.
- `PDM_PORT` suggests configurability that the underlying service does not currently use.
- Manual key bootstrapping may conflict with current package-owned initialization.
- LXC defaults are too small for a durable deployment.
- The documented backup process can archive a live SQLite database without ensuring consistency.
- The image lifecycle is neither reproducible nor automatically refreshed.
- There is no end-to-end test proving that the public API and privileged API can start and communicate.

## Severity definitions

- **Critical** — likely to produce stale, missing, insecure, or nonfunctional releases.
- **High** — materially weakens security, correctness, upgrade behavior, or recoverability.
- **Medium** — creates misleading behavior, operational fragility, or maintenance debt.
- **Low** — documentation, ergonomics, or polish issue that should still be corrected.

---

# Findings

## 1. Release workflow targets the wrong branch

**Severity:** Critical  
**Affected files:** `.github/workflows/docker-publish.yml`, `.github/workflows/lint.yml`

The repository default branch is `master`, but the publish and lint workflows only run for pushes to `main`.

### Impact

- Normal commits to the default branch do not trigger image publication.
- Lint and Compose validation do not protect the actual default branch.
- `latest` can remain stale indefinitely.
- Documentation may claim a release exists when no current workflow produced it.

### Required correction

Choose one branch name and use it consistently.

Preferred correction:

- Rename the default branch to `main`.
- Update local clones and branch protection rules.
- Verify every workflow references the new default branch.

Acceptable alternative:

- Retain `master` and update every workflow trigger accordingly.

### Acceptance criteria

- [ ] A push to the default branch triggers linting.
- [ ] A push to the default branch can trigger the intended publication workflow.
- [ ] Branch protection requires the relevant checks.
- [ ] A test commit proves the workflow runs on the default branch.

## 2. GHCR image path is inconsistent

**Severity:** Critical  
**Affected files:** `.github/workflows/docker-publish.yml`, `docker/docker-compose.yml`, `README.md`

The workflow constructs an image path from `${{ github.repository }}/pdm`, while the README and Compose file use `ghcr.io/willmortimer/pdm`.

### Impact

- The workflow can publish an image that users never pull.
- The documented image may be missing or stale.
- `docker compose pull` is not a reliable update mechanism.

### Required correction

Use one canonical image name everywhere.

Recommended canonical path:

```text
ghcr.io/willmortimer/proxmox-datacenter-manager-docker
```

Recommended tags:

```text
1.1-r1
1.1-r2
sha-<short-commit>
latest
```

`latest` should be a convenience alias only. Documentation and production examples should use immutable tags.

### Acceptance criteria

- [ ] Workflow, Compose, README, release notes, and examples use one image path.
- [ ] The published package is visible in GHCR.
- [ ] Pulling the documented immutable tag succeeds.
- [ ] Image labels identify the repository, commit, build time, and PDM version.

## 3. Repository target is behind the current PDM release line

**Severity:** Critical  
**Affected files:** `README.md`, `docker/Dockerfile`, release process

The repository describes PDM 1.0 Stable while current upstream releases are in the PDM 1.1 series.

PDM 1.1 includes security-relevant browser and HTML sanitization fixes in addition to significant functionality and reliability improvements.

### Impact

- Existing images may miss important fixes.
- Users cannot determine whether a locally rebuilt floating image contains 1.0 or 1.1 packages.
- The repository does not expose a clear compatibility matrix.

### Required correction

- Update the documented target to the current tested PDM release.
- Record the exact installed package version during CI.
- Include that version in OCI labels and generated release metadata.
- Publish a compatibility matrix for repository release versus PDM package version.

### Acceptance criteria

- [ ] CI captures `dpkg-query` output for all installed PDM packages.
- [ ] Release notes identify the exact package versions.
- [ ] A smoke test verifies the expected API version.
- [ ] Documentation distinguishes repository release numbers from upstream PDM package versions.

## 4. APT repository configuration uses an obsolete layout

**Severity:** High  
**Affected files:** `docker/Dockerfile`, `lxc/setup-lxc.sh`, `lxc/LXC-README.md`

The project currently writes a one-line `.list` file and places a key under `/etc/apt/trusted.gpg.d`.

Current Proxmox installation guidance uses:

- Deb822 `.sources` files.
- A key under `/usr/share/keyrings`.
- An explicit `Signed-By` field.
- `pdm-enterprise` or `pdm-no-subscription` as the repository component.
- The container meta-package for minimal Debian installations where appropriate.

Official installation documentation:

- https://pdm.proxmox.com/docs/installation.html

### Impact

- Package resolution can fail as repositories evolve.
- Trust configuration is broader than necessary.
- Docker and LXC installation logic can drift from upstream package expectations.

### Required correction

Use a Deb822 source definition similar to:

```text
Types: deb
URIs: http://download.proxmox.com/debian/pdm
Suites: trixie
Components: pdm-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
```

Support repository selection explicitly:

- `pdm-no-subscription` by default for experimental/community builds.
- `pdm-enterprise` only when a valid subscription and credentials are supplied.

Prefer the official container meta-package when it matches the intended minimal deployment.

### Acceptance criteria

- [ ] Docker and LXC use the same repository-selection logic.
- [ ] No key is installed into the global trusted keyring.
- [ ] Build tests fail clearly when the package repository cannot be reached.
- [ ] The installed package set is captured as a CI artifact.

## 5. Privileged API socket path is outdated

**Severity:** Critical  
**Affected file:** `docker/start-pdm.sh`

The entrypoint waits for:

```text
/run/proxmox-datacenter/privileged-api.sock
```

Current PDM uses a socket under the `proxmox-datacenter-manager` runtime directory, currently documented as:

```text
/run/proxmox-datacenter-manager/priv.sock
```

### Impact

- Every startup can wait for a socket that will never exist.
- The public API may start without proving that its privileged backend is ready.
- Health status can look superficially valid while privileged operations fail.

### Required correction

- Determine the socket path from the installed release or package service definition.
- Wait for the actual socket.
- Treat timeout as fatal rather than continuing with a warning.
- Verify socket ownership and mode.

### Acceptance criteria

- [ ] Startup does not incur an unnecessary timeout.
- [ ] Container startup fails when the privileged service does not create its socket.
- [ ] Smoke tests verify the public API can perform an operation that crosses the privileged socket.

## 6. ARM64 support is unverified and probably unsupported

**Severity:** High  
**Affected files:** `.github/workflows/docker-publish.yml`, `README.md`

The project advertises AMD64 and ARM64 images and attempts a multi-architecture build. Upstream PDM requirements and package availability are centered on x86-64/AMD64.

A successful QEMU build setup does not prove that required packages exist or that PDM operates correctly on ARM64.

### Impact

- CI can fail during package installation.
- A manifest can advertise an architecture that has never passed runtime testing.
- Users can assume support that does not exist upstream.

### Required correction

- Publish AMD64 only unless ARM64 package availability and runtime behavior are explicitly demonstrated.
- Add architecture-specific smoke tests before advertising another platform.

### Acceptance criteria

- [ ] The release manifest contains only tested architectures.
- [ ] README support claims match tested CI platforms.
- [ ] ARM64 is reintroduced only with a successful native or emulated end-to-end test and a documented support caveat.

## 7. LXC Tailscale installation does not ensure `curl` exists

**Severity:** High  
**Affected file:** `lxc/setup-lxc.sh`

The base package installation includes `wget`, but the Tailscale path later invokes `curl` without installing it.

### Impact

- Tailscale installation can fail on minimal Debian templates.
- The failure occurs after the LXC guest has already been created and partially configured.

### Required correction

Either:

- Install `curl` before using it, or
- Use `wget` consistently.

Add cleanup or rollback behavior when provisioning fails.

### Acceptance criteria

- [ ] Tailscale installation works from a fresh minimal Debian template.
- [ ] Failure produces a clear error and leaves the guest in a known state.
- [ ] A CI or nested test exercises the generated installation commands.

## 8. LXC network readiness timeout is not enforced

**Severity:** High  
**Affected file:** `lxc/setup-lxc.sh`

The provisioning script retries network access but continues after the loop even if connectivity never succeeds.

### Impact

- Subsequent APT commands fail with less useful errors.
- A partially provisioned container remains behind.
- Automation cannot reliably distinguish network failure from package failure.

### Required correction

Track whether connectivity succeeded and abort explicitly after the timeout.

Also prefer checking DNS plus HTTPS connectivity to the required repositories rather than relying only on ICMP.

### Acceptance criteria

- [ ] Provisioning exits nonzero when required repositories are unreachable.
- [ ] The error identifies DNS, routing, or TLS/repository reachability where possible.
- [ ] The script reports whether the container was retained or destroyed after failure.

## 9. Docker grants VPN privileges unconditionally

**Severity:** High  
**Affected file:** `docker/docker-compose.yml`

The main PDM container always receives:

- `NET_ADMIN`
- `SYS_MODULE`
- `/dev/net/tun`
- IPv4 forwarding

These privileges are present even when WireGuard and Tailscale are disabled.

### Impact

- The default attack surface is much larger than required.
- `SYS_MODULE` is especially inappropriate for a normal application container.
- The README description of a hardened deployment is inaccurate.

### Required correction

The default PDM service should receive no VPN-specific privileges.

Preferred design:

- Keep PDM unprivileged.
- Run Tailscale or WireGuard as an optional sidecar or host-level service.
- Enable the VPN service with a Compose profile.
- Route PDM traffic through that network intentionally.

At minimum:

- Remove `SYS_MODULE`.
- Grant `NET_ADMIN` and `/dev/net/tun` only in an explicit VPN override.

### Acceptance criteria

- [ ] Default `docker compose up` starts without VPN capabilities.
- [ ] `cap_drop: [ALL]` is used where compatible.
- [ ] `security_opt: [no-new-privileges:true]` is enabled where compatible.
- [ ] VPN-enabled deployments use a separate profile or override.

## 10. Port 8443 binds to every host interface

**Severity:** High  
**Affected file:** `docker/docker-compose.yml`

The current port mapping exposes PDM on all host IPv4 and IPv6 interfaces.

### Impact

- The management UI can unintentionally appear on public, user, storage, or untrusted networks.
- Deployment safety depends on undocumented host firewall behavior.

### Required correction

Use a safe default:

```yaml
ports:
  - "127.0.0.1:8443:8443"
```

Provide documented alternatives for:

- A specific management VLAN address.
- A Tailscale address.
- No published port when using an internal reverse-proxy network.

### Acceptance criteria

- [ ] Default Compose binds only to loopback or does not publish the port.
- [ ] Documentation explains how to expose PDM intentionally.
- [ ] Examples include firewall and management-network expectations.

## 11. `PDM_PORT` is misleading

**Severity:** Medium  
**Affected files:** `docker/start-pdm.sh`, `docker/docker-compose.yml`, `.env.example`, `README.md`

The entrypoint logs `PDM_PORT`, but the service is launched without a corresponding port argument or configuration update.

### Impact

- Users can change an environment variable that only changes log output.
- Reverse proxy and health-check examples can become inconsistent.

### Required correction

Remove `PDM_PORT` unless current PDM provides a supported way to change its listener.

Expose only the host-side port as a Compose variable:

```yaml
ports:
  - "127.0.0.1:${PDM_HOST_PORT:-8443}:8443"
```

### Acceptance criteria

- [ ] No environment variable claims to change an immutable internal listener.
- [ ] Health checks always target the actual internal service port.
- [ ] Documentation distinguishes container port from host port.

## 12. Manual authentication-key bootstrapping may be obsolete

**Severity:** High  
**Affected file:** `docker/start-pdm.sh`

The entrypoint manually creates authentication and CSRF key files under `/etc/proxmox-datacenter-manager`.

Current PDM packages have their own expected certificate, authentication, runtime, and service initialization layout. Reimplementing package initialization in shell creates upgrade risk.

### Impact

- Generated files can have outdated names, modes, ownership, or formats.
- Package upgrades may introduce migrations that the entrypoint bypasses.
- Certificate and ACME behavior can diverge from upstream expectations.

### Required correction

- Inspect package maintainer scripts and systemd units for the current release.
- Let package-owned tools initialize state wherever possible.
- Only reproduce initialization behavior that is strictly required in a non-systemd Docker environment.
- Add explicit tests for first boot and restart with persisted configuration.

### Acceptance criteria

- [ ] First boot works with an empty configuration volume.
- [ ] Restart works with persisted configuration.
- [ ] Upgrading an existing configuration volume is tested.
- [ ] Key and certificate paths match the installed PDM release.

## 13. LXC defaults are undersized

**Severity:** Medium  
**Affected files:** `lxc/setup-lxc.sh`, `lxc/LXC-README.md`

Current defaults use 2 GiB RAM and an 8 GB disk.

These values are suitable only for a constrained evaluation environment and leave little room for logs, package caches, metrics history, upgrades, or recovery operations.

### Required correction

Recommended defaults:

```text
CPU: 2 cores
Memory: 4096 MiB
Disk: 40 GiB
```

Allow an explicit `--minimal` or `--evaluation` profile for smaller values.

### Acceptance criteria

- [ ] Default resource values are appropriate for durable use.
- [ ] Minimal evaluation values are clearly labeled.
- [ ] The script validates numeric ranges.
- [ ] Disk usage and retention expectations are documented.

## 14. LXC feature flags are broader than necessary

**Severity:** Medium  
**Affected file:** `lxc/setup-lxc.sh`

The script always enables `nesting=1,keyctl=1`.

### Impact

- The LXC guest receives additional kernel-facing functionality without a documented requirement.
- The default configuration is less restrictive than necessary.

### Required correction

- Test whether PDM requires either feature.
- Disable both by default if they are unnecessary.
- Enable them only for an explicit feature that requires them.

### Acceptance criteria

- [ ] A standard PDM LXC deployment works without unnecessary feature flags.
- [ ] Each enabled LXC feature has a documented reason.

## 15. “Native HA” wording overstates what LXC provides

**Severity:** Medium  
**Affected files:** `README.md`, `lxc/LXC-README.md`

An LXC guest can participate in PVE guest-level HA when the surrounding cluster, quorum, networking, and storage support it. That does not make PDM itself an active/standby clustered application.

### Required correction

Use wording such as:

> Eligible for Proxmox VE guest-level HA when deployed on compatible clustered storage. PDM itself is not made into an active/standby application by this repository.

Also warn against hosting the only PDM instance entirely inside the same failure domain it is intended to diagnose.

### Acceptance criteria

- [ ] Documentation distinguishes guest HA from application HA.
- [ ] Failure-domain guidance is included.

## 16. Docker backup instructions can capture a live SQLite database

**Severity:** High  
**Affected file:** `DEPLOYMENT.md`

The documented backup command archives persistent directories while PDM may still be running.

### Impact

- The SQLite database can be captured in an inconsistent state.
- A backup can appear successful but fail during restoration.
- Authentication keys and remote credentials can be copied without encryption.

### Required correction

Support one or more safe approaches:

1. Stop the container before creating a filesystem archive.
2. Use SQLite online backup functionality.
3. Take an atomic snapshot of the underlying filesystem or volume.

Backups must include:

- PDM state/database.
- Configuration and authentication material.
- Any required remote certificate state.
- A manifest containing image digest and PDM package versions.

Backups should be encrypted and periodically restore-tested.

### Acceptance criteria

- [ ] Documentation does not recommend archiving a live database without a consistency mechanism.
- [ ] A restore procedure is tested.
- [ ] The recovered deployment passes the smoke test.
- [ ] Backup encryption and retention expectations are documented.

## 17. Reverse-proxy examples disable backend TLS verification

**Severity:** Medium  
**Affected files:** `docker/docker-compose.traefik.yml`, `DEPLOYMENT.md`

The current examples rely on `insecureSkipVerify` or equivalent behavior for the connection between the reverse proxy and PDM.

### Impact

- The proxy cannot authenticate the backend.
- A compromised internal network can undermine the expected TLS boundary.

### Required correction

Preferred order:

1. Use PDM directly with a certificate managed by its supported certificate/ACME mechanism.
2. Trust a private CA or the explicit PDM backend certificate.
3. Use verification bypass only as a clearly labeled evaluation fallback.

### Acceptance criteria

- [ ] Secure backend verification is the primary documented configuration.
- [ ] Insecure examples are visibly labeled as evaluation-only.

## 18. Image builds are not reproducible

**Severity:** High  
**Affected file:** `docker/Dockerfile`, release process

The image currently combines:

- A floating `debian:trixie` base.
- Unpinned APT packages.
- A floating `latest` image tag.
- No recorded package manifest.

Full bit-for-bit reproducibility is difficult when consuming a live APT repository, but the project can still create traceable and repeatable release inputs.

### Required correction

- Pin the Debian base image by digest.
- Use immutable repository release tags.
- Capture exact installed package versions.
- Record the base-image digest and APT package manifest as release artifacts.
- Rebuild intentionally when security updates land.

Recommended base declaration pattern:

```dockerfile
FROM debian:trixie@sha256:<verified-digest>
```

Recommended release semantics:

```text
<PDM-major>.<PDM-minor>-r<repository-revision>
```

Example:

```text
1.1-r1
1.1-r2
```

### Acceptance criteria

- [ ] Every release resolves to one immutable image digest.
- [ ] Base-image digest is visible in source control.
- [ ] Exact installed package versions are attached to the release.
- [ ] `latest` is never the only documented deployment tag.

## 19. No scheduled rebuild exists

**Severity:** High  
**Affected file:** `.github/workflows/docker-publish.yml`

An image built from Debian and Proxmox packages does not receive operating-system or package security fixes after publication.

### Required correction

Run a scheduled rebuild at least weekly.

The scheduled workflow should:

- Resolve the pinned base digest through Renovate updates.
- Install current packages from the selected PDM release repository.
- Run linting and smoke tests.
- Scan the resulting image.
- Publish only when all required gates pass.
- Produce a new immutable repository revision when package contents change.

A scheduled job should not silently mutate an existing immutable tag.

### Acceptance criteria

- [ ] A weekly schedule is configured.
- [ ] Rebuild failures generate a visible notification.
- [ ] Existing immutable tags never move.
- [ ] Security rebuilds produce a new revision tag.

## 20. No image vulnerability gate exists

**Severity:** High  
**Affected area:** CI/CD

The repository does not currently scan the final image.

### Required correction

Use Trivy or Grype against the built image.

Recommended policy:

- Fail on fixable critical vulnerabilities.
- Report high vulnerabilities.
- Allow documented exceptions only with an expiration date and rationale.
- Upload SARIF results to GitHub code scanning where available.

Scanning must occur against the final runtime image, not only the repository filesystem.

### Acceptance criteria

- [ ] Every pull request image is scanned.
- [ ] Every release image is scanned.
- [ ] Results are retained as artifacts or code-scanning findings.
- [ ] Exceptions are explicit and time-bounded.

## 21. No SBOM or provenance is published

**Severity:** High  
**Affected area:** CI/CD

Users cannot easily determine which Debian, Proxmox, Tailscale, and other packages are inside an image.

### Required correction

Enable BuildKit-generated:

- SPDX or CycloneDX SBOM.
- SLSA-compatible provenance attestation.

Example build-push-action configuration:

```yaml
provenance: mode=max
sbom: true
```

Retain a human-readable package manifest as a release artifact as well.

### Acceptance criteria

- [ ] Each published digest has an attached SBOM.
- [ ] Each published digest has provenance attestation.
- [ ] Package versions can be inspected without starting the image.

## 22. Published images are not signed

**Severity:** High  
**Affected area:** CI/CD

The repository does not provide a cryptographic identity binding between GitHub Actions and a published image digest.

### Required correction

Use Cosign keyless signing with GitHub Actions OIDC.

Sign by immutable digest, not by mutable tag.

Publish verification instructions such as:

```bash
cosign verify \
  --certificate-identity-regexp='https://github.com/willmortimer/proxmox-datacenter-manager-docker/.github/workflows/.*' \
  --certificate-oidc-issuer='https://token.actions.githubusercontent.com' \
  ghcr.io/willmortimer/proxmox-datacenter-manager-docker@sha256:<digest>
```

### Acceptance criteria

- [ ] Every release digest is signed.
- [ ] Verification succeeds using the documented repository identity.
- [ ] Signing occurs only after all release gates pass.

## 23. Base-image digest updates are not automated

**Severity:** Medium  
**Affected area:** dependency management

Dependabot currently covers GitHub Actions only. It does not manage Docker base-image digest updates.

### Required correction

Add Renovate with Docker digest pinning enabled.

Renovate should:

- Detect a new digest for the configured Debian tag.
- Open a pull request that updates the digest.
- Include release notes where available.
- Trigger the full build, scan, and smoke-test pipeline.
- Avoid automerging major distribution changes.

### Acceptance criteria

- [ ] Base-image digest updates arrive as reviewable pull requests.
- [ ] The full CI pipeline runs on each update.
- [ ] Distribution-version changes require manual review.

## 24. No end-to-end PDM smoke test exists

**Severity:** Critical  
**Affected area:** CI/CD

Linting and `docker compose config` validation prove only that files parse. They do not prove that PDM installs, starts, creates its privileged socket, serves the API, or survives a restart with persisted state.

### Required correction

Add an AMD64 smoke-test workflow that:

1. Builds the image.
2. Starts a disposable container with temporary persistent directories.
3. Waits for the actual privileged API socket.
4. Waits for the public HTTPS endpoint.
5. Calls the version endpoint.
6. Records installed package versions.
7. Verifies both required PDM processes are alive.
8. Restarts the container using the same persisted state.
9. Verifies the API works after restart.
10. Fails if startup logs contain known fatal errors.

Recommended checks:

```bash
docker exec pdm-test test -S /run/proxmox-datacenter-manager/priv.sock
curl --fail --insecure --silent \
  https://127.0.0.1:<ephemeral-port>/api2/json/version
```

The exact socket path and endpoint must be derived from the tested PDM release rather than permanently assumed.

### Acceptance criteria

- [ ] Pull requests cannot merge when the smoke test fails.
- [ ] Release publication cannot occur when the smoke test fails.
- [ ] First boot and persisted restart are both tested.
- [ ] Test logs and package manifests are retained on failure.

## 25. Runtime process supervision remains fragile

**Severity:** High  
**Affected file:** `docker/start-pdm.sh`

The Docker entrypoint manually supervises rsyslog, the privileged API, the public API, and optional VPN daemons.

### Impact

- Process reaping, shutdown ordering, logging, and failure propagation are easy to implement incorrectly.
- One shell script must track upstream service changes.
- VPN concerns are mixed into the PDM process lifecycle.

### Required correction

Preferred options, in order:

1. Keep LXC as the primary containerized path and use systemd normally.
2. For Docker, separate VPN processes into sidecars.
3. Use a minimal init such as `tini` for signal forwarding and zombie reaping.
4. Keep the entrypoint focused only on PDM-specific startup requirements.
5. Treat failure of either required PDM process as fatal.

### Acceptance criteria

- [ ] PID 1 behavior is deliberate and tested.
- [ ] SIGTERM produces a bounded graceful shutdown.
- [ ] A child-process crash causes the container to exit nonzero.
- [ ] VPN daemon failure does not silently corrupt PDM lifecycle behavior.

## 26. Default Docker hardening is incomplete

**Severity:** High  
**Affected files:** `docker/Dockerfile`, `docker/docker-compose.yml`

The public API runs as `www-data`, but the container itself starts as root because it must launch the privileged API. Additional controls are therefore important.

### Required correction

Evaluate and apply where compatible:

```yaml
security_opt:
  - no-new-privileges:true
cap_drop:
  - ALL
read_only: true
tmpfs:
  - /run
  - /tmp
```

Then add back only the exact capabilities and writable paths demonstrated to be necessary.

Other required controls:

- Explicit user and group ownership for bind mounts.
- Resource limits or documented resource recommendations.
- Log rotation.
- A restrictive internal network.
- No Docker socket mount.
- No host PID, IPC, or privileged mode.

### Acceptance criteria

- [ ] Required capabilities are documented individually.
- [ ] Default deployment contains no VPN capabilities.
- [ ] Writable paths are enumerated.
- [ ] Container security settings are exercised by the smoke test.

## 27. Documentation presents experimental behavior too confidently

**Severity:** Medium  
**Affected files:** `README.md`, `DEPLOYMENT.md`, `lxc/LXC-README.md`

Terms such as “production-ready,” “hardened,” “multi-arch,” and “native HA” currently overstate the demonstrated behavior.

### Required correction

Documentation should clearly distinguish:

- Upstream-supported installation paths.
- Repository-supported experimental paths.
- Features proven by CI.
- Features that are best-effort or unverified.
- Security tradeoffs introduced by Docker.
- LXC guest-level HA versus PDM application HA.

### Acceptance criteria

- [ ] Every major support claim maps to a test or upstream guarantee.
- [ ] Docker is labeled experimental.
- [ ] LXC is labeled the preferred repository pathway.
- [ ] ISO and Debian VM recommendations are retained without implying that this repository should reproduce ISO installation.

---

# Target build and release architecture

## Goals

The release system should provide:

- Traceable inputs.
- Immutable output tags.
- Automated security refreshes.
- A verifiable software supply chain.
- Runtime validation against the actual PDM service architecture.
- Clear separation between upstream PDM version and repository packaging revision.

## Recommended version model

Use:

```text
<PDM major>.<PDM minor>-r<repository revision>
```

Examples:

```text
1.1-r1
1.1-r2
```

Meaning:

- `1.1` identifies the intended PDM release family.
- `r1`, `r2`, and later revisions identify changes to the container packaging, base image, installed package set, or security rebuild.

Also publish:

```text
sha-<short commit>
```

`latest` may point to the newest validated stable repository release, but it must never be the recommended pinned deployment reference.

## Required image metadata

Every image should include OCI labels for:

- Source repository.
- Commit SHA.
- Build timestamp.
- Repository release version.
- Installed PDM package version.
- Debian base image digest.
- License.
- Documentation URL.

## Recommended CI stages

### Stage 1: Static validation

- ShellCheck.
- Hadolint.
- Compose validation.
- YAML validation.
- Markdown link checking.

### Stage 2: Build

- AMD64 build only until other architectures are proven.
- Pinned Debian digest.
- Build cache enabled.
- Package manifest exported.

### Stage 3: Runtime smoke test

- Start PDM.
- Verify privileged socket.
- Verify public API.
- Verify package version.
- Restart with persisted state.
- Verify API again.

### Stage 4: Security validation

- Trivy or Grype final-image scan.
- Secret scan against repository and image history where practical.
- Policy gate for fixable critical vulnerabilities.

### Stage 5: Supply-chain metadata

- BuildKit SBOM.
- BuildKit provenance.
- Human-readable package manifest.

### Stage 6: Publication

- Push immutable version tag.
- Push commit tag.
- Optionally update `latest` after successful validation.
- Never overwrite an existing immutable tag.

### Stage 7: Signing

- Cosign keyless signature using GitHub OIDC.
- Sign by digest.
- Publish verification instructions.

## Scheduled rebuild policy

Run the release pipeline weekly even when repository source has not changed.

A scheduled rebuild should determine whether any of the following changed:

- Debian base digest.
- Debian security packages.
- Proxmox PDM package versions.
- Tailscale package versions, when included.
- Other installed runtime dependencies.

When package contents change:

- Publish a new repository revision.
- Do not move an existing immutable tag.
- Update the package manifest and attestations.

When no contents change:

- Record a successful validation run without publishing a duplicate release.

## Renovate policy

Renovate should manage:

- Debian base-image digest.
- GitHub Action versions.
- Cosign action/version.
- Trivy or Grype action/version.
- Docker tooling actions.

Renovate should not automatically merge:

- Debian release transitions.
- PDM major-version transitions.
- Changes that alter package repository channels.

---

# Runtime architecture direction

## LXC pathway

LXC should become the primary path documented by this repository because it retains:

- systemd service units.
- package maintainer scripts.
- journald.
- native APT upgrades.
- Proxmox guest backups.
- Optional PVE guest-level HA.
- Lower architectural divergence from upstream.

The LXC script should be treated as infrastructure provisioning, not as an opaque installer.

Recommended future direction:

- Split guest creation from guest configuration.
- Support cloud-init or an Ansible role for repeatable configuration.
- Make repository channel explicit.
- Add idempotent rerun behavior.
- Add a `--destroy-on-failure` option.
- Add static IP and VLAN options.
- Add firewall configuration or documented rules.
- Add unattended-upgrades policy with controlled reboot behavior.
- Add backup-job examples.

## Docker pathway

Docker should remain available for experimentation and constrained environments, with explicit limitations.

Recommended architecture:

- One PDM application container.
- No integrated VPN daemon by default.
- Optional Tailscale or WireGuard sidecar/profile.
- Minimal init for PID 1 behavior.
- Explicit writable volumes only.
- Loopback-only port publishing by default.
- Immutable image reference.
- Strong smoke and upgrade tests.

The Docker implementation should avoid reimplementing more of systemd and package initialization than absolutely necessary.

---

# Upgrade and migration testing

The repository should test more than clean installation.

Required scenarios:

1. Empty-volume first boot.
2. Restart using the same persisted volumes.
3. Upgrade from the previous repository release.
4. Upgrade across a PDM minor release where supported.
5. Backup followed by restore into the same image version.
6. Backup followed by restore into the next repository revision.
7. Failed privileged service startup.
8. Corrupt or missing configuration file behavior.
9. Read-only or incorrectly owned volume behavior.

Each release should document tested upgrade origins.

Example:

```text
Tested upgrades:
- 1.1-r1 -> 1.1-r2
- 1.0-r3 -> 1.1-r1
```

Do not claim arbitrary upgrade compatibility without testing it.

---

# Operational guidance

## Network placement

PDM is a management-plane service and should be placed on a dedicated management network where possible.

Recommended controls:

- Do not expose PDM directly to the public internet.
- Restrict access to a management VLAN, VPN, or identity-aware proxy.
- Restrict outbound access to required Proxmox, PBS, DNS, NTP, package, and certificate endpoints.
- Document required ports by feature.
- Keep the only PDM instance outside the failure domain it is expected to diagnose when practical.

## Backups

Back up at minimum:

- PDM database/state.
- PDM configuration.
- Authentication keys and certificates.
- Remote certificate state.
- Image digest and package manifest.

Backups should be:

- Consistent.
- Encrypted.
- Stored outside the deployment host.
- Retained under a documented policy.
- Periodically restored and smoke-tested.

## Updates

Docker images are replaced, not patched in place.

Recommended update flow:

1. Pull a specific immutable image tag.
2. Verify its Cosign signature.
3. Read the release notes and package manifest.
4. Create a consistent backup.
5. Start the new image using the existing persistent state.
6. Run the post-upgrade smoke test.
7. Retain the previous image digest for rollback.

LXC deployments should use normal APT lifecycle management with controlled backups and upgrade testing.

---

# Phased implementation plan

## Phase 0: Stop misleading releases

- [ ] Fix default branch/workflow mismatch.
- [ ] Fix GHCR image path mismatch.
- [ ] Remove or disable ARM64 publication.
- [ ] Mark Docker as experimental.
- [ ] Stop recommending `latest` as the deployment reference.

## Phase 1: Restore functional correctness

- [ ] Update the PDM APT repository configuration.
- [ ] Correct the privileged socket path.
- [ ] Rework package-owned initialization and key creation.
- [ ] Fix LXC Tailscale installation.
- [ ] Enforce LXC network timeout failure.
- [ ] Increase LXC defaults.
- [ ] Add a first-boot and restart smoke test.

## Phase 2: Harden runtime defaults

- [ ] Remove unconditional VPN capabilities.
- [ ] Remove `SYS_MODULE`.
- [ ] Bind PDM to loopback by default.
- [ ] Add `no-new-privileges` and capability dropping where compatible.
- [ ] Separate VPN into optional profiles or sidecars.
- [ ] Add log rotation and resource guidance.

## Phase 3: Build trustworthy releases

- [ ] Pin Debian by digest.
- [ ] Add immutable `1.1-rN` tags.
- [ ] Add weekly scheduled rebuilds.
- [ ] Add Trivy or Grype scanning.
- [ ] Add BuildKit SBOM.
- [ ] Add BuildKit provenance.
- [ ] Add Cosign keyless signing.
- [ ] Add Renovate for Docker digest updates.
- [ ] Publish package manifests.

## Phase 4: Recovery and upgrade assurance

- [ ] Replace live-tar backup guidance.
- [ ] Add tested backup/restore procedures.
- [ ] Test upgrades from the previous repository release.
- [ ] Publish a compatibility matrix.
- [ ] Add automated post-upgrade validation.

## Phase 5: Improve LXC as the preferred repository deployment

- [ ] Separate creation and configuration steps.
- [ ] Add idempotent configuration.
- [ ] Add static IP, VLAN, and firewall options.
- [ ] Add controlled update automation.
- [ ] Add native backup scheduling examples.
- [ ] Document PVE guest HA accurately.

---

# Definition of done for the next stable repository release

The next repository release should not be called stable until all of the following are true:

- [ ] Default-branch CI runs successfully.
- [ ] One canonical GHCR image path is used everywhere.
- [ ] AMD64 image builds successfully from a pinned Debian digest.
- [ ] Current supported PDM packages install successfully.
- [ ] The actual privileged API socket is created and validated.
- [ ] The public version endpoint responds successfully.
- [ ] Persisted restart succeeds.
- [ ] Final image passes the vulnerability policy.
- [ ] SBOM and provenance are attached.
- [ ] Image digest is signed with Cosign.
- [ ] Immutable release tag is published.
- [ ] Exact PDM and Debian package versions are recorded.
- [ ] Default Compose deployment has no VPN privileges.
- [ ] Default port binding is restricted.
- [ ] Backup and restore have been tested.
- [ ] Docker limitations and LXC preference are documented honestly.

## Upstream references

- PDM documentation: https://pdm.proxmox.com/docs/
- Installation guidance: https://pdm.proxmox.com/docs/installation.html
- System administration guidance: https://pdm.proxmox.com/docs/sysadmin.html
- Roadmap and release changes: https://pdm.proxmox.com/docs/roadmap.html

## Maintenance note

This document records an audit at a point in time. PDM is still evolving, so socket paths, package names, service behavior, supported architectures, repository channels, and installation guidance must be revalidated against upstream documentation during every PDM minor-version upgrade.
