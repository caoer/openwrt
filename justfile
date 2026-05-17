default_target := "192.168.61.1"
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

# Copy all baked files into build tree (applied at image creation)
bake-config:
    rm -rf files
    cp -a nix/files files
    chmod +x files/etc/init.d/* 2>/dev/null || true

# Fetch EasyTier aarch64 binary into baked files
fetch-easytier version="2.6.4":
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p nix/files/usr/sbin
    if [ -x nix/files/usr/sbin/easytier-core ]; then
        echo "easytier-core already present, skipping download"
        exit 0
    fi
    echo "Downloading EasyTier v{{version}} for aarch64..."
    curl -fSL "https://github.com/EasyTier/EasyTier/releases/download/v{{version}}/easytier-linux-aarch64-v{{version}}.zip" -o /tmp/easytier-aarch64.zip
    cd /tmp && unzip -o easytier-aarch64.zip
    cp /tmp/easytier-linux-aarch64/easytier-core nix/files/usr/sbin/easytier-core
    cp /tmp/easytier-linux-aarch64/easytier-cli nix/files/usr/sbin/easytier-cli
    chmod +x nix/files/usr/sbin/easytier-core nix/files/usr/sbin/easytier-cli
    rm -rf /tmp/easytier-aarch64.zip /tmp/easytier-linux-aarch64
    echo "EasyTier binaries installed to nix/files/usr/sbin/"

# Fetch sing-box aarch64 binary from GitHub releases
fetch-singbox version="1.14.0-alpha.2":
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p nix/files/usr/sbin
    if [ -x nix/files/usr/sbin/sing-box ]; then
        echo "sing-box already present, skipping download"
        exit 0
    fi
    echo "Downloading sing-box v{{version}} for linux-arm64..."
    curl -fSL "https://github.com/SagerNet/sing-box/releases/download/v{{version}}/sing-box-{{version}}-linux-arm64.tar.gz" -o /tmp/sing-box-arm64.tar.gz
    tar -xzf /tmp/sing-box-arm64.tar.gz -C /tmp
    cp "/tmp/sing-box-{{version}}-linux-arm64/sing-box" nix/files/usr/sbin/sing-box
    chmod +x nix/files/usr/sbin/sing-box
    rm -rf /tmp/sing-box-arm64.tar.gz "/tmp/sing-box-{{version}}-linux-arm64"
    echo "sing-box installed to nix/files/usr/sbin/"

# Build with baked config + easytier + singbox
build-full jobs="$(nproc)": fetch-easytier fetch-singbox bake-config
    make -j{{jobs}} V=s

# Flash firmware to target (fire-and-forget, agent-safe)
flash target=default_target:
    #!/usr/bin/env bash
    set -euo pipefail
    FW=$(ls -t {{image_glob}} 2>/dev/null | head -1)
    if [ -z "$FW" ]; then
        echo "ERROR: No firmware image found. Run 'just build' first."
        exit 1
    fi
    echo "Firmware: $FW"
    echo "Target:   root@{{target}}"
    echo ""
    echo "Uploading..."
    scp -O "$FW" "root@{{target}}:/tmp/firmware.bin"
    echo "Verifying image integrity..."
    ssh -o ConnectTimeout=10 "root@{{target}}" "sysupgrade -T /tmp/firmware.bin"
    echo ""
    echo "Scheduling sysupgrade (fire-and-forget)..."
    ssh -o ConnectTimeout=10 "root@{{target}}" 'printf "#!/bin/sh\nsleep 5\nsysupgrade -n /tmp/firmware.bin\n" > /tmp/do-upgrade.sh && chmod +x /tmp/do-upgrade.sh && /tmp/do-upgrade.sh </dev/null >/dev/null 2>&1 &'
    echo "Sysupgrade scheduled. Waiting 120s for reboot..."
    sleep 120
    echo "Checking if device is back..."
    ssh -o ConnectTimeout=10 "root@{{target}}" "cat /etc/openwrt_release" && echo "SUCCESS" || echo "FAILED — device not responding"

# Verify flash was successful
verify target=default_target:
    ssh -o ConnectTimeout=10 "root@{{target}}" "cat /etc/openwrt_release; echo ''; iw dev | grep -E 'ssid|txpower|channel'"

# Pull live config from router back to nix/files
pull-config target=default_target:
    #!/usr/bin/env bash
    set -euo pipefail
    for f in network wireless firewall dhcp system; do
        scp -O "root@{{target}}:/etc/config/$f" "nix/files/etc/config/$f"
        echo "Pulled: $f"
    done
    echo "Done. Config files updated in nix/files/etc/config/"

# Clean build artifacts
clean:
    make clean

# Deep clean (removes toolchain too)
distclean:
    make distclean
