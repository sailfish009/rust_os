use super::{DeviceLocation, CONFIG_ADDR, CONFIG_DATA};

/// From http://wiki.osdev.org/PCI#Configuration_Space_Access_Mechanism_.231
unsafe fn pci_read_u32(bus: u8, slot: u8, func: u8, offset: u8) -> u32 {
    assert!(offset % 4 == 0, "offset must be 4-byte aligned");

    let address: u32 = (
        ((bus as u32) << 16) | ((slot as u32) << 11) | ((func as u32) << 8) | (offset as u32) | (0x80000000u32)
    ) as u32;

    /* write out the address */
    asm!("out dx, eax" :: "{dx}"(CONFIG_ADDR), "{eax}"(address) :: "intel","volatile");
    let inp: u32;
    asm!("in eax, dx" : "={eax}"(inp) : "{dx}"(CONFIG_DATA) :: "intel","volatile");
    inp
}

unsafe fn pci_write_u32(bus: u8, slot: u8, func: u8, offset: u8, value: u32) {
    assert!(offset % 4 == 0, "offset must be 4-byte aligned");

    let address: u32 = (
        ((bus as u32) << 16) | ((slot as u32) << 11) | ((func as u32) << 8) | (offset as u32) | (0x80000000u32)
    ) as u32;

    /* write out the address */
    asm!("out dx, eax" :: "{dx}"(CONFIG_ADDR), "{eax}"(address) :: "intel","volatile");
    asm!("out dx, eax" :: "{dx}"(CONFIG_DATA), "{eax}"(value)   :: "intel","volatile");
}

pub fn pci_read_device(loc: DeviceLocation, offset: u8) -> u32 {
    unsafe {
        pci_read_u32(loc.0, loc.1, loc.2, offset)
    }
}

pub fn pci_write_device(loc: DeviceLocation, offset: u8, value: u32) {
    unsafe {
        pci_write_u32(loc.0, loc.1, loc.2, offset, value)
    }
}
