use alloc::vec::Vec;
use alloc::boxed::Box;
use spin::Mutex;

mod ata_pio;
mod virtio;

pub trait BlockDevice: Send {
    /// Returns success status
    fn init(&mut self) -> bool;

    /// Capacity in bytes
    fn capacity_bytes(&mut self) -> u64;

    fn read(&mut self, sector: u64) -> Vec<u8>;

    fn write(&mut self, sector: u64, data: Vec<u8>);
}



pub struct DiskController {
    pub driver: Option<Box<BlockDevice>>
}
impl DiskController {
    pub const fn new() -> DiskController {
        DiskController {
            driver: None
        }
    }

    pub unsafe fn init(&mut self) {
        rprintln!("DiskIO: Selecting driver...");

        // Initialize VirtIO controller if available
        self.driver = virtio::VirtioBlock::try_new();
        if self.driver.is_some() {
            rprintln!("DiskIO: VirtIO-blk selected");
        } else {

            // Initialize ATA PIO controller if available
            self.driver = ata_pio::AtaPio::try_new();
            if self.driver.is_some() {
                rprintln!("DiskIO: ATA PIO selected");
            } else {
                rprintln!("DiskIO: No supported devices found");
            }
        }

        if self.driver.is_some() {
            let ok = if let Some(ref mut driver) = self.driver {
                driver.init()
            } else { unreachable!() };

            if !ok {
                rprintln!("DiskIO: Driver initialization failed");
                self.driver = None;
            }
        }

        if let Some(ref mut driver) = self.driver {
            rprintln!("DiskIO: Device capacity: {} bytes", driver.capacity_bytes());
        }
    }

    pub unsafe fn map<T>(&mut self, f: &mut FnMut(&mut Box<BlockDevice>) -> T) -> Option<T> {
        if let Some(ref mut driver) = self.driver {
            Some(f(driver))
        }
        else {
            None
        }
    }

    pub fn read(&mut self, sector: u64, count: u64) -> Vec<Vec<u8>> {
        if let Some(ref mut driver) = self.driver {
            rprintln!("DiskIO: Read sectors {}..{}", sector, sector + count);
            (0..count).map(|offset| driver.read(sector + offset)).collect()
        } else {
            panic!("DiskIO: No driver available");
        }
    }
}

// Create static pointer mutex with spinlock to make networking thread-safe
pub static DISK_IO: Mutex<DiskController> = Mutex::new(DiskController::new());

pub fn init() {
    let mut dc = DISK_IO.lock();
    unsafe {
        dc.init();
    }
}