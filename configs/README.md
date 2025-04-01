The standard values that we need to change for a V3 are the following:

## Serdes Board
CONFIG_I2C_IOEXPANDER_SER_MAX9295=y
CONFIG_I2C_IOEXPANDER_DESER_MAX9296=y

## RGBs
CONFIG_NV_VIDEO_ISX031=y                                                       

## RealSense
CONFIG_VIDEO_D4XX=m                                                                                                                                                                                   
CONFIG_VIDEO_D4XX_SERDES=y   
CONFIG_VIDEO_D4XX=m
CONFIG_VIDEO_D4XX_SERDES=y   

## Modem
CONFIG_USB_SERIAL_QUALCOMM=m
CONFIG_USB_SERIAL_WWAN=m
CONFIG_USB_SERIAL_OPTION=m
CONFIG_USB_NET_QMI_WWAN=m

## Display

Needed enabling:

CONFIG_TEGRA_NVDISPLAY=y
CONFIG_DRM_TEGRA=m
CONFIG_TEGRA_HOST1X=m
CONFIG_TEGRA_HOST1X_FIREWALL=y

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
CONFIG_TEGRA_NVDISPLAY

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
