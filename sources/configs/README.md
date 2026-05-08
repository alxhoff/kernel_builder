The standard values that we need to change for a V3 are the following:

## Serdes Board
CONFIG_I2C_IOEXPANDER_SER_MAX9295=y
CONFIG_I2C_IOEXPANDER_DESER_MAX9296=y

## RGBs
CONFIG_NV_VIDEO_ISX031=y                                                       

## RealSense
CONFIG_VIDEO_D4XX=m
CONFIG_VIDEO_D4XX_SERDES=y

## Modem
CONFIG_USB_SERIAL_QUALCOMM=m
CONFIG_USB_SERIAL_WWAN=m
CONFIG_USB_SERIAL_OPTION=m
CONFIG_USB_NET_QMI_WWAN=m

## Display

Needed enabling:

CONFIG_TEGRA_DP=y
CONFIG_DRM_TEGRA=m

Enabled by default:

CONFIG_DRM=y
CONFIG_DRM_KMS_HELPER=y
CONFIG_DRM_MIPI_DSI=y
CONFIG_DRM_BRIDGE=y
CONFIG_DRM_PANEL=y
CONFIG_DRM_PANEL_BRIDGE=y
CONFIG_TEGRA_DC=y
CONFIG_TEGRA_DP=y
CONFIG_TEGRA_DPHDCP=y
CONFIG_TEGRA_HDMI2_0=y
CONFIG_TEGRA_HDA_DC=y
CONFIG_TEGRA_NVADSP=m
CONFIG_HDMI=y

Unsure:

CONFIG_TEGRA_NVDISPLAY=y

## Multi-path TCP

CONFIG_MPTCP=y
CONFIG_INET_MPTCP_DIAG=m
CONFIG_MPTCP_IPV6=y

Depends on (but should already be enabled)

CONFIG_NET=y
CONFIG_INET=y

## Panic logger

After patching in the driver

CONFIG_CARTKEN_PANIC_LOGGER=m

## Vanilla 5.1.2 tegra diff to modified vanilla BSP

+ARCH_TEGRA_239_SOC y #Enables support for Tegra 239, which is the Orin SoC family (you need this).
+CARTKEN_PANIC_LOGGER m
+CRYPTO_DEV_TEGRA_FDE m
+DMA_BCM2835 y #DMA engine driver for Broadcom BCM2835, used in Raspberry Pi. Likely irrelevant for Jetson.
+DMA_SUN6I m #DMA driver for Allwinner SoCs (sun6i). Irrelevant on Tegra.
+DMI_SYSFS y # Exposes DMI info to userspace (like dmidecode). Harmless; unrelated to display.
+DRM_RCAR_LVDS m
+IMX_SDMA m #Smart DMA controller on NXP i.MX SoCs. Not needed for Jetson.
+INET_MPTCP_DIAG m
+K3_DMA y #TI K3 DMA controller (used in TI SoCs). Unrelated to Jetson.
+MPTCP_IPV6 y
+MV_XOR y #Marvell XOR DMA engine. Used on Marvell ARM platforms. Irrelevant for Tegra.
+NV_VIDEO_ISX031 y
+OWL_DMA y #DMA engine for Actions Semi OWL SoCs (rare). Not needed.
+VIDEO_D4XX m
+VIDEO_D4XX_SERDES y

