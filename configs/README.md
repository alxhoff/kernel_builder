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

## Panic logger

After patching in the driver

CONFIG_CARTKEN_PANIC_LOGGER=m
