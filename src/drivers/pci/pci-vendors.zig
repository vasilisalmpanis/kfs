pub fn identifyClass(class: u8, subclass: u8) [:0]const u8 {
    switch (class) {
        0x00 => {
            switch (subclass) {
                0x00 => return "Non-VGA unclassified device",
                0x01 => return "VGA compatible unclassified device",
                0x05 => return "Image coprocessor",
                else => return "Unclassified device"
            }
        },
        0x01 => {
            switch (subclass) {
                0x00 => return "SCSI storage controller",
                0x01 => return "IDE interface",
                0x02 => return "Floppy disk controller",
                0x03 => return "IPI bus controller",
                0x04 => return "RAID bus controller",
                0x05 => return "ATA controller",
                0x06 => return "SATA controller",
                0x07 => return "Serial Attached SCSI controller",
                0x08 => return "Non-Volatile memory controller",
                0x09 => return "Universal Flash Storage controller",
                0x80 => return "Mass storage controller",
                else => return "Mass storage controller"
            }
        },
        0x02 => {
            switch (subclass) {
                0x00 => return "Ethernet controller",
                0x01 => return "Token ring network controller",
                0x02 => return "FDDI network controller",
                0x03 => return "ATM network controller",
                0x04 => return "ISDN controller",
                0x05 => return "WorldFip controller",
                0x06 => return "PICMG controller",
                0x07 => return "Infiniband controller",
                0x08 => return "Fabric controller",
                0x80 => return "Network controller",
                else => return "Network controller"
            }
        },
        0x03 => {
            switch (subclass) {
                0x00 => return "VGA compatible controller",
                0x01 => return "XGA compatible controller",
                0x02 => return "3D controller",
                0x80 => return "Display controller",
                else => return "Display controller"
            }
        },
        0x04 => {
            switch (subclass) {
                0x00 => return "Multimedia video controller",
                0x01 => return "Multimedia audio controller",
                0x02 => return "Computer telephony device",
                0x03 => return "Audio device",
                0x80 => return "Multimedia controller",
                else => return "Multimedia controller"
            }
        },
        0x05 => {
            switch (subclass) {
                0x00 => return "RAM memory",
                0x01 => return "FLASH memory",
                0x02 => return "CXL",
                0x80 => return "Memory controller",
                else => return "Memory controller"
            }
        },
        0x06 => {
            switch (subclass) {
                0x00 => return "Host bridge",
                0x01 => return "ISA bridge",
                0x02 => return "EISA bridge",
                0x03 => return "MicroChannel bridge",
                0x04 => return "PCI bridge",
                0x05 => return "PCMCIA bridge",
                0x06 => return "NuBus bridge",
                0x07 => return "CardBus bridge",
                0x08 => return "RACEway bridge",
                0x09 => return "Semi-transparent PCI-to-PCI bridge",
                0x0a => return "InfiniBand to PCI host bridge",
                0x80 => return "Bridge",
                else => return "Bridge"
            }
        },
        0x07 => {
            switch (subclass) {
                0x00 => return "Serial controller",
                0x01 => return "Parallel controller",
                0x02 => return "Multiport serial controller",
                0x03 => return "Modem",
                0x04 => return "GPIB controller",
                0x05 => return "Smard Card controller",
                0x80 => return "Communication controller",
                else => return "Communication controller"
            }
        },
        0x08 => {
            switch (subclass) {
                0x00 => return "PIC",
                0x01 => return "DMA controller",
                0x02 => return "Timer",
                0x03 => return "RTC",
                0x04 => return "PCI Hot-plug controller",
                0x05 => return "SD Host controller",
                0x06 => return "IOMMU",
                0x80 => return "System peripheral",
                0x99 => return "Timing Card",
                else => return "Generic system peripheral"
            }
        },
        0x09 => {
            switch (subclass) {
                0x00 => return "Keyboard controller",
                0x01 => return "Digitizer Pen",
                0x02 => return "Mouse controller",
                0x03 => return "Scanner controller",
                0x04 => return "Gameport controller",
                0x80 => return "Input device controller",
                else => return "Input device controller"
            }
        },
        0x0a => {
            switch (subclass) {
                0x00 => return "Generic Docking Station",
                0x80 => return "Docking Station",
                else => return "Docking station"
            }
        },
        0x0b => {
            switch (subclass) {
                0x00 => return "386",
                0x01 => return "486",
                0x02 => return "Pentium",
                0x10 => return "Alpha",
                0x20 => return "Power PC",
                0x30 => return "MIPS",
                0x40 => return "Co-processor",
                else => return "Processor"
            }
        },
        0x0c => {
            switch (subclass) {
                0x00 => return "FireWire (IEEE 1394)",
                0x01 => return "ACCESS Bus",
                0x02 => return "SSA",
                0x03 => return "USB controller",
                0x04 => return "Fibre Channel",
                0x05 => return "SMBus",
                0x06 => return "InfiniBand",
                0x07 => return "IPMI Interface",
                0x08 => return "SERCOS interface",
                0x09 => return "CANBUS",
                0x80 => return "Serial bus controller",
                else => return "Serial bus controller"
            }
        },
        0x0d => {
            switch (subclass) {
                0x00 => return "IRDA controller",
                0x01 => return "Consumer IR controller",
                0x10 => return "RF controller",
                0x11 => return "Bluetooth",
                0x12 => return "Broadband",
                0x20 => return "802.1a controller",
                0x21 => return "802.1a controller",
                0x80 => return "Wireless controller",
                else => return "Wireless controller"
            }
        },
        0x0e => {
            switch (subclass) {
                0x00 => return "I2O",
                else => return "Intelligent controller"
            }
        },
        0x0f => {
            switch (subclass) {
                0x01 => return "Satellite TV controller",
                0x02 => return "Satellite audio communication controller",
                0x03 => return "Satellite voice communication controller",
                0x04 => return "Satellite data communication controller",
                else => return "Satellite communications controller"
            }
        },
        0x10 => {
            switch (subclass) {
                0x00 => return "Network and computing encryption device",
                0x10 => return "Entertainment encryption device",
                0x80 => return "Encryption controller",
                else => return "Encryption controller"
            }
        },
        0x11 => {
            switch (subclass) {
                0x00 => return "DPIO module",
                0x01 => return "Performance counters",
                0x10 => return "Communication synchronizer",
                0x20 => return "Signal processing management",
                0x80 => return "Signal processing controller",
                else => return "Signal processing controller"
            }
        }, 
        0x12 => {
            switch (subclass) {
                0x00 => return "Processing accelerators",
                0x01 => return "SNIA Smart Data Accelerator Interface (SDXI) controller",
                else => return "Processing accelerators"
            }
        }, 
        0x13 => {
            switch (subclass) {
                else => return "Non-Essential Instrumentation"
            }
        },
        0x40 => {
            switch (subclass) {
                else => return "Coprocessor"
            }
        },                                   
        else => return "unknown class"
    }
}


pub fn identifyDevice(vendor_id: u16, device_id: u16) [:0]const u8 {
    switch (vendor_id) {
        0x1234 => {
            switch (device_id) {
                0x1111 => return "Bochs Graphics Adaptor",
                else => return "Technical Corp., unknown device id"
            }
        },
        0x1AF4 => {
            switch (device_id) {
                0x1000 => return "Virtio network device",
                0x1001 => return "Virtio block device",
                0x1002 => return "Virtio memory balloon",
                0x1003 => return "Virtio console",
                0x1004 => return "Virtio SCSI",
                0x1005 => return "Virtio RNG",
                0x1009 => return "Virtio filesystem",
                0x1041 => return "Virtio 1.0 network device",
                0x1042 => return "Virtio 1.0 block device",
                0x1043 => return "Virtio 1.0 console",
                0x1044 => return "Virtio 1.0 RNG",
                0x1045 => return "Virtio 1.0 balloon",
                0x1046 => return "Virtio 1.0 ioMemory",
                0x1047 => return "Virtio 1.0 remote processor messaging",
                0x1048 => return "Virtio 1.0 SCSI",
                0x1049 => return "Virtio 9P transport",
                0x104a => return "Virtio 1.0 WLAN MAC",
                0x104b => return "Virtio 1.0 remoteproc serial link",
                0x104d => return "Virtio 1.0 memory balloon",
                0x1050 => return "Virtio 1.0 GPU",
                0x1051 => return "Virtio 1.0 clock/timer",
                0x1052 => return "Virtio 1.0 input",
                0x1053 => return "Virtio 1.0 socket",
                0x1054 => return "Virtio 1.0 crypto",
                0x1055 => return "Virtio 1.0 signal distribution device",
                0x1056 => return "Virtio 1.0 pstore device",
                0x1057 => return "Virtio 1.0 IOMMU",
                0x1058 => return "Virtio 1.0 mem",
                0x1059 => return "Virtio 1.0 sound",
                0x105a => return "Virtio 1.0 file system",
                0x105b => return "Virtio 1.0 pmem",
                0x105c => return "Virtio 1.0 rpmb",
                0x105d => return "Virtio 1.0 mac80211-hwsim",
                0x105e => return "Virtio 1.0 video encoder",
                0x105f => return "Virtio 1.0 video decoder",
                0x1060 => return "Virtio 1.0 SCMI",
                0x1061 => return "Virtio 1.0 nitro secure module",
                0x1062 => return "Virtio 1.0 I2C adapter",
                0x1063 => return "Virtio 1.0 watchdog",
                0x1064 => return "Virtio 1.0 can",
                0x1065 => return "Virtio 1.0 dmabuf",
                0x1066 => return "Virtio 1.0 parameter server",
                0x1067 => return "Virtio 1.0 audio policy",
                0x1068 => return "Virtio 1.0 Bluetooth",
                0x1069 => return "Virtio 1.0 GPIO",
                0x1110 => return "QEMU Inter-VM shared memory device",
                else => return "Red Hat, Inc, unknown device id"
            }
        },
        0x1B36 => {
            switch (device_id) {
                0x0001 => return "QEMU PCI-PCI bridge",
                0x0002 => return "QEMU PCI 16550A Adapter",
                0x0003 => return "QEMU PCI Dual-port 16550A Adapter",
                0x0004 => return "QEMU PCI Quad-port 16550A Adapter",
                0x0005 => return "QEMU PCI Test Device",
                0x0006 => return "PCI Rocker Ethernet switch device",
                0x0007 => return "PCI SD Card Host Controller Interface",
                0x0008 => return "QEMU PCIe Host bridge",
                0x0009 => return "QEMU PCI Expander bridge",
                0x000a => return "PCI-PCI bridge (multiseat)",
                0x000b => return "QEMU PCIe Expander bridge",
                0x000c => return "QEMU PCIe Root port",
                0x000d => return "QEMU XHCI Host Controller",
                0x000e => return "QEMU PCIe-to-PCI bridge",
                0x0010 => return "QEMU NVM Express Controller",
                0x0011 => return "QEMU PVPanic device",
                0x0013 => return "QEMU UFS Host Controller",
                0x0100 => return "QXL paravirtual graphic card",
                else => return "Red Hat, Inc, unknown device id"
            }
        },
        0x8086 => {
            switch (device_id) {
                0x1237 => return "440FX - 82441FX PMC",
                0x7000 => return "82371SB PIIX3 ISA",
                0x7010 => return "82371SB PIIX3 IDE",
                0x7020 => return "82371SB PIIX3 USB",
                0x7110 => return "82371AB/EB/MB PIIX4 ISA",
                0x7111 => return "82371AB/EB/MB PIIX4 IDE",
                0x7112 => return "82371AB/EB/MB PIIX4 USB",
                0x7113 => return "82371AB/EB/MB PIIX4 ACPI",
                0x100E => return "82540EM Gigabit Ethernet Controller",
                else => return "Intel, unknown device id"
            }
        },
        else => return "unknown vendor id"
    }
}
