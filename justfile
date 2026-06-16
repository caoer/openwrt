default_target := "192.168.8.1"
profile := "robot"
device := "glinet_gl-mt3600be"
image_glob := "bin/targets/mediatek/filogic/openwrt-mediatek-filogic-" + device + "-squashfs-sysupgrade.bin"

# Install feeds and apply seed config
setup:
    ./scripts/feeds update -a
    ./scripts/feeds install -a
    cp nix/config/seed.config .config
    make defconfig

# Full firmware build (parallel)
build jobs="$(nproc)":
    make -j{{jobs}} V=s 2>&1 | tee build.log

# Quick rebuild after config/package change (no toolchain rebuild)
rebuild jobs="$(nproc)":
    make -j{{jobs}} V=s

# Show current diffconfig
diffconfig:
    ./scripts/diffconfig.sh

# Save current .config back to seed
save-config:
    ./scripts/diffconfig.sh > nix/config/seed.config

# Copy a profile's baked files into build tree (applied at image creation)
bake-config:
    rm -rf files
    cp -a nix/profiles/{{profile}}/files files
    chmod +x files/etc/init.d/* files/etc/uci-defaults/* files/usr/sbin/* 2>/dev/null || true

# Fetch EasyTier aarch64 binary into baked files
fetch-easytier version="2.6.4":
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p nix/profiles/{{profile}}/files/usr/sbin
    if [ -x nix/profiles/{{profile}}/files/usr/sbin/easytier-core ]; then
        echo "easytier-core already present, skipping download"
        exit 0
    fi
    echo "Downloading EasyTier v{{version}} for aarch64..."
    curl -fSL "https://github.com/EasyTier/EasyTier/releases/download/v{{version}}/easytier-linux-aarch64-v{{version}}.zip" -o /tmp/easytier-aarch64.zip
    unzip -o /tmp/easytier-aarch64.zip -d /tmp
    cp /tmp/easytier-linux-aarch64/easytier-core nix/profiles/{{profile}}/files/usr/sbin/easytier-core
    cp /tmp/easytier-linux-aarch64/easytier-cli nix/profiles/{{profile}}/files/usr/sbin/easytier-cli
    chmod +x nix/profiles/{{profile}}/files/usr/sbin/easytier-core nix/profiles/{{profile}}/files/usr/sbin/easytier-cli
    rm -rf /tmp/easytier-aarch64.zip /tmp/easytier-linux-aarch64
    echo "EasyTier binaries installed to nix/profiles/{{profile}}/files/usr/sbin/"

# Fetch sing-box aarch64 binary from GitHub releases
fetch-singbox version="1.14.0-alpha.2":
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p nix/profiles/{{profile}}/files/usr/sbin
    if [ -x nix/profiles/{{profile}}/files/usr/sbin/sing-box ]; then
        echo "sing-box already present, skipping download"
        exit 0
    fi
    echo "Downloading sing-box v{{version}} for linux-arm64..."
    curl -fSL "https://github.com/SagerNet/sing-box/releases/download/v{{version}}/sing-box-{{version}}-linux-arm64.tar.gz" -o /tmp/sing-box-arm64.tar.gz
    tar -xzf /tmp/sing-box-arm64.tar.gz -C /tmp
    cp "/tmp/sing-box-{{version}}-linux-arm64/sing-box" nix/profiles/{{profile}}/files/usr/sbin/sing-box
    chmod +x nix/profiles/{{profile}}/files/usr/sbin/sing-box
    rm -rf /tmp/sing-box-arm64.tar.gz "/tmp/sing-box-{{version}}-linux-arm64"
    echo "sing-box installed to nix/profiles/{{profile}}/files/usr/sbin/"

# Build with baked profile config + easytier (robot profile: no singbox).
# Override profile: `just profile=zeratul build-full` (also fetch-singbox first).
build-full jobs="$(nproc)": fetch-easytier bake-config
    make -j{{jobs}} V=s

# Flash firmware over SSH — agent-safe AND survives operator WiFi/SSH disconnection.
# Re-execs itself detached (setsid+nohup -> /tmp log), so a dropped link mid-flash
# cannot abort it; the post-reboot verify reconnects on its own. Two modes:
#   mode=keep  (default) — config-preserving sysupgrade: keeps /etc/config + the files
#              listed in /etc/sysupgrade.conf (per-device identity, mode). Unit returns
#              reachable on the SAME path (WiFi/mesh). Use to re-flash deployed units.
#   mode=clean — sysupgrade -n: wipes config; new baked image config applies fresh. Unit
#              self-recovers WiFi via baked STA creds; then re-provision to restore mesh
#              identity. Reach it via the robot jump host at 192.168.8.1 (mesh id is gone).
# Usage: just flash <ip> [keep|clean]   (keep = config-preserving, default)
flash target=default_target mode="keep":
    #!/usr/bin/env bash
    set -euo pipefail
    # Detach so a WiFi/SSH drop can't kill the flash (run from any host; tmux not required).
    if [ -z "${FLASH_DETACHED:-}" ]; then
        LOG="/tmp/flash-{{target}}-$(date +%Y%m%d-%H%M%S).log"
        echo "Flashing {{target}} (mode={{mode}}) — detaching so a link drop can't abort it."
        echo "  watch:  tail -f $LOG"
        # setsid is Linux-only (util-linux); macOS lacks it. nohup alone survives
        # SIGHUP on a link/terminal drop, which is what we need here.
        if command -v setsid >/dev/null 2>&1; then
            FLASH_DETACHED=1 setsid nohup just flash {{target}} {{mode}} >"$LOG" 2>&1 </dev/null &
        else
            FLASH_DETACHED=1 nohup just flash {{target}} {{mode}} >"$LOG" 2>&1 </dev/null &
        fi
        echo "  detached PID $!"
        exit 0
    fi
    case "{{mode}}" in
        keep)  SYSUP="sysupgrade"    ;;
        clean) SYSUP="sysupgrade -n" ;;
        *) echo "ERROR: mode must be 'keep' or 'clean'"; exit 1 ;;
    esac
    FW=$(ls -t {{image_glob}} 2>/dev/null | head -1)
    [ -n "$FW" ] || { echo "ERROR: No firmware image found. Run 'just build' first."; exit 1; }
    echo "Firmware: $FW"
    echo "Target:   root@{{target}}  (mode={{mode}})"
    LOCAL_SHA=$(sha256sum "$FW" | cut -d' ' -f1)
    echo "Local SHA256: $LOCAL_SHA"
    echo "Uploading..."
    scp -O "$FW" "root@{{target}}:/tmp/firmware.bin"
    echo "Verifying SHA256 on device..."
    REMOTE_SHA=$(ssh -o ConnectTimeout=10 "root@{{target}}" "sha256sum /tmp/firmware.bin | cut -d' ' -f1")
    if [ "$LOCAL_SHA" != "$REMOTE_SHA" ]; then
        echo "ERROR: SHA256 mismatch! Upload corrupted."
        echo "  local:  $LOCAL_SHA"
        echo "  remote: $REMOTE_SHA"
        exit 1
    fi
    echo "SHA256 match: $REMOTE_SHA"
    echo "Verifying image metadata (sysupgrade -T)..."
    ssh -o ConnectTimeout=10 "root@{{target}}" "sysupgrade -T /tmp/firmware.bin"
    echo "Scheduling $SYSUP (fire-and-forget on device)..."
    ssh -o ConnectTimeout=10 "root@{{target}}" "printf '#!/bin/sh\nsleep 5\n$SYSUP /tmp/firmware.bin\n' > /tmp/do-upgrade.sh && chmod +x /tmp/do-upgrade.sh && /tmp/do-upgrade.sh </dev/null >/dev/null 2>&1 &"
    echo "Scheduled. Polling for reboot + WiFi reassoc (up to 5 min)..."
    for i in $(seq 1 30); do
        sleep 10
        if ssh -o ConnectTimeout=8 -o BatchMode=yes -o StrictHostKeyChecking=accept-new "root@{{target}}" "cat /etc/openwrt_release" 2>/dev/null; then
            echo "SUCCESS — {{target}} back after ~$((i*10))s (mode={{mode}})"
            exit 0
        fi
    done
    echo "FAILED — {{target}} not reachable after 300s."
    echo "  If mode=clean over mesh: the unit lost its mesh identity — reach it via the"
    echo "  robot jump host at 192.168.8.1 and re-provision (locus-routers/fleet-telemetry/onboard-robot.sh)."
    exit 1

# Verify flash was successful
verify target=default_target:
    ssh -o ConnectTimeout=10 "root@{{target}}" "cat /etc/openwrt_release; echo ''; iw dev | grep -E 'ssid|txpower|channel'"

# Pull live config from router back to nix/files
pull-config target=default_target:
    #!/usr/bin/env bash
    set -euo pipefail
    for f in network wireless firewall dhcp system; do
        scp -O "root@{{target}}:/etc/config/$f" "nix/profiles/{{profile}}/files/etc/config/$f"
        echo "Pulled: $f"
    done
    echo "Done. Config files updated in nix/profiles/{{profile}}/files/etc/config/"

# Clean build artifacts
clean:
    make clean

# Deep clean (removes toolchain too)
distclean:
    make distclean
