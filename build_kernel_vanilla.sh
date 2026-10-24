#!/bin/bash

# Vanilla kernel build for Exynos 2100 - o1s (Galaxy S21) only
# Builds a mainline-style kernel for o1s device variant only

set -e

export ARCH=arm64
export PLATFORM_VERSION=11
export ANDROID_MAJOR_VERSION=r
export SEC_BUILD_CONF_VENDOR_BUILD_OS=13

# Start from base arm64 defconfig
make ARCH=arm64 defconfig

# Disable non-Exynos platforms
./scripts/config --disable ARCH_AGILEX
./scripts/config --disable ARCH_SUNXI
./scripts/config --disable ARCH_ALPINE
./scripts/config --disable ARCH_BCM2835
./scripts/config --disable ARCH_BCM_IPROC
./scripts/config --disable ARCH_BERLIN
./scripts/config --disable ARCH_BRCMSTB
./scripts/config --disable ARCH_K3
./scripts/config --disable ARCH_LAYERSCAPE
./scripts/config --disable ARCH_LG1K
./scripts/config --disable ARCH_HISI
./scripts/config --disable ARCH_MEDIATEK
./scripts/config --disable ARCH_MESON
./scripts/config --disable ARCH_MVEBU
./scripts/config --disable ARCH_MXC
./scripts/config --disable ARCH_QCOM
./scripts/config --disable ARCH_RENESAS
./scripts/config --disable ARCH_ROCKCHIP
./scripts/config --disable ARCH_SEATTLE
./scripts/config --disable ARCH_STRATIX10
./scripts/config --disable ARCH_SYNQUACER
./scripts/config --disable ARCH_TEGRA
./scripts/config --disable ARCH_SPRD
./scripts/config --disable ARCH_THUNDER
./scripts/config --disable ARCH_THUNDER2
./scripts/config --disable ARCH_UNIPHIER
./scripts/config --disable ARCH_VEXPRESS
./scripts/config --disable ARCH_XGENE
./scripts/config --disable ARCH_ZX
./scripts/config --disable ARCH_ZYNQMP

# Keep Exynos enabled
# Enable Exynos 2100 specific options
./scripts/config --enable SOC_EXYNOS2100
./scripts/config --enable EXYNOS_PM_DOMAINS
./scripts/config --enable EXYNOS_CPUIDLE
./scripts/config --enable EXYNOS_THERMAL
./scripts/config --enable EXYNOS_ACME
./scripts/config --enable EXYNOS_DSU_FREQ
./scripts/config --enable EXYNOS_BUS
./scripts/config --enable EXYNOS_PCIE
./scripts/config --enable EXYNOS_PCIE_GEN2_S2MPU
./scripts/config --enable EXYNOS_IOMMU
./scripts/config --enable EXYNOS_ADC
./scripts/config --enable SND_SOC_SAMSUNG

# Essential kernel features
./scripts/config --enable IKCONFIG
./scripts/config --enable IKCONFIG_PROC
./scripts/config --set-val LOG_BUF_SHIFT 21
./scripts/config --enable MODULES
./scripts/config --enable MODULE_UNLOAD
./scripts/config --enable MODVERSIONS
./scripts/config --enable BPF
./scripts/config --enable BPF_SYSCALL
./scripts/config --enable BPF_JIT
./scripts/config --enable NET
./scripts/config --enable INET
./scripts/config --enable IPV6
./scripts/config --enable NETFILTER
./scripts/config --enable NF_CONNTRACK
./scripts/config --enable NF_NAT

# Storage (UFS for o1s)
./scripts/config --enable SCSI
./scripts/config --enable BLK_DEV_SD
./scripts/config --enable SCSI_UFSHCD
./scripts/config --enable SCSI_UFSHCD_PLATFORM
./scripts/config --enable SCSI_UFS_DWC_TC_PLATFORM
./scripts/config --enable SCSI_UFS_EXYNOS
./scripts/config --enable DM_CRYPT
./scripts/config --enable DM_VERITY
./scripts/config --enable DM_VERITY_AVB
./scripts/config --enable ZRAM

# Filesystems
./scripts/config --enable EXT4_FS
./scripts/config --enable F2FS_FS
./scripts/config --enable VFAT_FS
./scripts/config --enable EXFAT_FS

# Crypto
./scripts/config --enable CRYPTO_AES_ARM64
./scripts/config --enable CRYPTO_SHA256_ARM64
./scripts/config --enable CRYPTO_SHA1_ARM64_CE
./scripts/config --enable CRYPTO_SHA2_ARM64_CE

# Debug
./scripts/config --enable DEBUG_INFO
./scripts/config --disable DEBUG_INFO_REDUCED

# o1s device detection
./scripts/config --enable SEC_DETECT

# Clean local version
./scripts/config --set-str LOCALVERSION "-vanilla-o1s"
./scripts/config --enable LOCALVERSION_AUTO

# Build kernel + o1s DTBOs only
make ARCH=arm64 -j$(nproc) Image.gz
make ARCH=arm64 -j$(nproc) dtbs_install INSTALL_DTBS_PATH=./dtbs_o1s

# Copy o1s DTBOs
mkdir -p artifacts
cp arch/arm64/boot/Image.gz artifacts/
cp arch/arm64/boot/dts/exynos/samsung/o1s/*.dtbo artifacts/ 2>/dev/null || true

echo "Build complete. o1s artifacts:"
ls -la artifacts/