# Robot Router — Config & Setup

OpenWrt `robot` profile for the **coScene robot fleet**. Routers ride on robots
(Unitree / Orin PCs), uplink over WiFi, and join the `locus-mesh` EasyTier overlay
for remote fleet management.

- **Device:** GL.iNet GL-MT3600BE (2.5GbE WiFi 7 travel router)
- **Target:** `glinet_gl-mt3600be` on `mediatek/filogic` (MT7981B / Filogic)
- **Repo / branch:** `.repos/openwrt` @ `feat/robot-fleet`
- **Profile dir:** `nix/profiles/robot/files/` (the baked rootfs overlay)
- **Sibling profile:** `zeratul` (ZT's daily-driver proxy router, sing-box baked) —
  build it with `just profile=zeratul build-full`.

---

## Credentials (verified)

| What | Value |
|---|---|
| **root password** | `66666666` |
| root shadow hash | `$6$mWWRYvnb5YkQRP0t$7nZm8pEjKNfzPDD7gQBNd69OuoYLxxABEWhyb4fMQv32DCziuoSp/UnzmkGDM.E.K4elQKVuaa1rIy0DBHo4B0` |
| mesh network name | `locus-mesh` |
| mesh shared secret (baked, all units) | `JGT/8a725S3tCwARkbedUyy39br+X+D60jgKhw1bHKo=` |
| WiFi STA SSID | `coScene-Robot` |
| WiFi STA PSK | ⚠️ **PLACEHOLDER** `REPLACE_WITH_FACTORY_PSK` — real factory PSK still pending |
| provision-script default WiFi key | `99999999` |

> Hash is the SHA-512 crypt of `66666666` (`openssl passwd -6`), baked into
> `etc/shadow`. Live device and baked image kept in sync — a clean flash re-applies
> this password rather than silently reverting to an older one.

**Authorized SSH keys** (`etc/dropbear/authorized_keys`):
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDs7AQ9ntFHCz/IMWdIcO/n7QtgtttOcnRQUAdZd7Gxl coscene-dev
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGr3CRZjOlGWTv3z6L6kARv5+xN7F08NqUmWw/xgU6eH mike@mike-dev
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN1u3AqF9mHO8FJP1NN91j1c2UT4BPONphKroHnOk2Rc z@mac-m4
```
The `coscene-dev` private key lives on the Mac at `~/.ssh/keys/coscene-dev` (sops-nix
deployed; defined in `.repos/osfiles/lib/ssh/access.nix`). A **clean flash wipes keys** —
keep that key handy for recovery.

---

## SSH access

```bash
# On-desk / directly reachable (NORMAL mode LAN):
ssh root@192.168.8.1

# Deployed unit, via the robot's own jump host (fleet path):
ssh -J coscene-eva-46 root@192.168.8.1

# IPv6 link-local rescue when IPv4 is dead (find iface with `ndp -an`):
ssh root@fe80::9683:c4ff:fedc:dbe5%en7
```

---

## Network (baked config)

| Role | Interface | Setting |
|---|---|---|
| LAN (robot-facing) | `br-lan` ← `eth1` | static `192.168.8.1/24` (NORMAL) — robot plugs in, gets DHCP, reaches console |
| WAN (wired, optional) | `eth0` | DHCP, metric 20 — harmless if unplugged |
| WAN6 | `eth0` | DHCPv6 |
| **WWAN (primary uplink)** | 5GHz STA | DHCP, metric 10 → preferred default route |
| Mesh | `etmesh` (tun) | EasyTier `locus-mesh`, proto none |
| ULA prefix | — | `fd76:82d1:3e1a::/48` |

**DHCP** (NORMAL): dnsmasq authoritative on `lan`, range `192.168.8.100–.249`, 12h
lease. Ignored on `wan` / `wwan`.

**WiFi** (`etc/config/wireless`): `radio0` (2.4GHz) **off**; `radio1` (5GHz, HE80,
country US) on with one `sta_uplink` wifi-iface in **STA/client** mode → SSID
`coScene-Robot` (`psk2`). Baked **enabled** so a flashed/wiped unit auto-rejoins WiFi
for self-recovery — but the key is still the placeholder above.

**Firewall** — three zones: `lan` (accept all), `wan` (covers wan/wan6/**wwan**;
input REJECT, forward DROP, masq + mtu_fix), `mesh` (input ACCEPT for remote SSH mgmt,
forward REJECT — no routing). Only `lan→wan` forwarding. Default in/forward REJECT.

---

## Build & flash

Build env: Nix flake (host deps for fresh machines). On a box that already has
`build-essential`, run `just build` directly — **do not** mix `nix develop` with an
existing native `build_dir` (toolchain mismatch segfaults cached binaries).

```bash
just setup            # feeds update/install -a; cp nix/config/seed.config .config; make defconfig
just build-full       # deps: fetch-easytier (v2.6.4 aarch64) + bake-config, then make -j V=s
                      #   robot profile = NO sing-box. zeratul: `just profile=zeratul build-full` (fetch-singbox first)
just flash <ip> [keep|clean]
just verify <ip>
just pull-config <ip> # pull live network/wireless/firewall/dhcp/system back into the profile
```

Image glob: `bin/targets/mediatek/filogic/openwrt-mediatek-filogic-glinet_gl-mt3600be-squashfs-sysupgrade.bin`

**Flash modes** (the recipe re-execs itself detached via `setsid nohup` → `/tmp/flash-*.log`,
so a dropped WiFi/SSH link mid-flash cannot abort it; polls up to 300s for reboot):

- `keep` (default) — config-preserving `sysupgrade`. Keeps `/etc/config` **plus** the
  files in `etc/sysupgrade.conf` (`/etc/glrobot.conf`, `/etc/glrobot.mode` — the
  per-device identity + mode survive). Unit returns reachable on the same WiFi/mesh path.
- `clean` — `sysupgrade -n`. **Wipes all config + SSH keys + mesh identity.** Baked
  image config applies fresh; unit self-recovers WiFi via baked STA creds; then
  **re-provision** to restore mesh identity. Reach it via the robot jump host at
  `192.168.8.1`.

**Baked packages of note** (`nix/config/seed.config`): `glrobot-base` (fleet
scripts), full LuCI, `iperf3`, `kmod-tun`, `kmod-nft-tproxy/socket`, `kmod-tcp-bbr`,
plus baked-in kernel support that **cannot** be grafted at runtime:
`kmod-inet-diag` + `kmod-nf-conntrack-netlink` (OpenClash) and `zram-swap` +
`kmod-zram` (OOM headroom — 512MB router OOM-loops mihomo without swap). OpenClash
*userspace* deps install from the apk feed at runtime once these kmods are present.

---

## EasyTier mesh & provisioning

EasyTier mesh is **template-based, rendered at provision time**. The flow:

1. **Baked into firmware:** `etc/easytier/config.toml.template` with `@NODE_NAME@`
   and `@MESH_IP@` placeholders. The mesh secret, bootstrap peers, and network
   settings are shared across **all** robot routers (baked, identical).
2. **Per-unit identity:** the operator drops `/etc/glrobot.conf` on the router with
   two values — `NODE_NAME` (e.g. `eva-46-router`) and `MESH_IP` (e.g.
   `10.144.146.46`).
3. **Provision:** `glrobot-provision` runs (at firstboot via `uci-defaults`, or
   manually). It `sed`s the template → `/etc/easytier/config.toml`, sets the
   hostname, enables the init script, and starts the mesh.

**Unprovisioned ≠ broken.** With no `/etc/glrobot.conf`, `glrobot-provision` exits 0,
no `config.toml` is rendered, and EasyTier never starts — that's a deliberate
unprovisioned unit. Provision it to bring the mesh up.

The mesh itself is **`locus-mesh`** — joins two bootstrap peers at
`89.208.247.77:11010` and `104.224.152.92:11010` over TCP+UDP, encrypted, on a
`10.144.0.0/16` overlay (`/16`, so `MESH_IP` is rendered as `…/16`) using the
`etmesh` tun device, MTU 1380. A 3rd live bootstrap (`64.186.236.100`,
dmit-us-lax-2) is available for redundancy. **Do not** re-add `64.186.233.167` /
`23.252.105.155` — PAUSED/dead since 2026-06-07.

### Full provision process

1. **Flash** robot firmware onto the GL-MT3600BE: `just flash <ip> clean`.
2. **Onboard** using `locus-routers/fleet-telemetry/onboard-robot.sh`:
   ```bash
   .repos/locus-routers/fleet-telemetry/onboard-robot.sh <node> <mesh-ip> [router-ssh]
   # e.g. onboard-robot.sh eva-02 10.144.146.2 root@192.168.8.1
   ```

That script:
- Decrypts the per-node EasyTier credential from sops (`et_credential_<node>`).
- Writes `/etc/glrobot.conf` with `NODE_NAME`, `MESH_IP`, `ET_CREDENTIAL`, and WiFi
  STA creds, then runs `glrobot-provision`.
- Gap-fills what glrobot-provision misses post-boot: reloads hostname into the kernel,
  re-derives AP ssid via `glrobot-mode`, sets STA uplink on the live sta section(s).
- Adds the mesh-IP scrape target to `victoria-metrics/prometheus.yml`, deploys to
  the VM, and verifies the target shows `health=up`.
- Verifies end to end: kernel hostname, exporter nodename, AP ssid, mesh tun0 IP,
  node-exporter binding, STA uplink ssid.

`/etc/glrobot.conf` seed format (`glrobot.conf.example`):
```
NODE_NAME="eva-46-router"
MESH_IP="10.144.146.46"
#WIFI_SSID="coScene-Robot"   # baked fleet-uniform; override only if this unit differs
#WIFI_KEY="..."
# LAN IP is NOT per-seed — owned by the mode switch (see below).
```

---

## Mode switch (NORMAL ↔ GATEWAY)

LAN IP is owned by `glrobot-mode`, **not** the seed. Driven by the physical BTN_0
slide switch (`hotplug.d/button/00-mode-switch`) and restored at boot
(`init.d/glrobot-mode`, default NORMAL). `glrobot-mode {normal|gateway}` to set manually.

| | NORMAL | GATEWAY |
|---|---|---|
| LAN | `192.168.8.1/24` | `192.168.123.1/24` (robot internal segment gateway) |
| DHCP | `.100` + 150 | `.220`–`.230` (static `.161/.164/.120` never ask) |
| NTP server | off | **on** (fixes PC2 cold-boot clock=1970) |
| Extra | — | mesh→LAN SSH DNAT `:2222 → 192.168.123.164:22` (PC2 / Orin NX) |
| LED | white | blue |

Factory net cannot reach the zero-auth DDS segment: `wan/wwan→lan` is default-deny and
never bridged.

---

## Quirks / gotchas

1. **The `/32` netmask bug** (root cause of an earlier "can't connect"): `list ipaddr
   '192.168.8.1/24'` gets firstboot-converted to `option ipaddr '192.168.8.1'` with
   **no netmask** → netifd assigns `/32` on `br-lan`. Link up, dnsmasq running, but no
   IPv4 client can reach it (IPv6 still works — separate prefix). **Fix** (commit
   `f8a03c6a55`): use `option ipaddr` + `option netmask '255.255.255.0'`, not the CIDR
   list form. Live recovery: `uci set network.lan.netmask=255.255.255.0; uci commit
   network; /etc/init.d/network restart`.
2. **WiFi STA PSK is a placeholder** — fleet WiFi self-recovery won't actually work
   until the real `coScene-Robot` factory PSK replaces `REPLACE_WITH_FACTORY_PSK`.
3. **Clean flash wipes keys + mesh identity.** Robot profile bakes only `coscene-dev` —
   keep `~/.ssh/keys/coscene-dev` available, or use the jump host.
4. **Don't clean-flash the daily driver.** This profile is for fleet units; ZT's
   daily-driver router uses the `zeratul` profile (rollback image staged at
   `~/Downloads/gl-mt3600be-zeratul-zram-d11bc1c.bin`).
