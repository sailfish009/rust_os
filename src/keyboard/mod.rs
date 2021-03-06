mod key;
mod keyreader;
mod keymap;
mod event;

use spin::Mutex;
use cpuio::UnsafePort;

use util::io_wait;

use self::keyreader::KeyReader;
pub use self::event::{KeyboardEvent, KeyboardEventType};
pub use self::key::Key;

use alloc::vec::Vec;

// PS/2 ports
const PS2_DATA:     u16 = 0x60; // rw
const PS2_STATUS:   u16 = 0x64; // r-
const PS2_COMMAND:  u16 = 0x64; // -w

// PIC commands
const PIC_CMD_EOI:  u8 = 0x20;
const PIC_CMD_INIT: u8 = 0x11;

// Sensible timeout
const IO_WAIT_TIMEOUT: usize = 1000;

// Event buffer
const EVENT_BUFFER_SIZE: usize = 100;


pub struct Keyboard {
    enabled: bool,
    offset: u8,
    data_port: UnsafePort<u8>,
    status_port: UnsafePort<u8>,
    command_port: UnsafePort<u8>,
    key_reader: KeyReader,
    /// Items that are not yet moved to KEYBOARD_EVENTS
    pending_buffer: Vec<KeyboardEvent>,
}

impl Keyboard {
    pub const unsafe fn new() -> Keyboard {
        Keyboard {
            enabled: false,
            offset: 0,
            data_port: UnsafePort::new(PS2_DATA),
            status_port: UnsafePort::new(PS2_STATUS),
            command_port: UnsafePort::new(PS2_COMMAND),
            key_reader: KeyReader::new(),
            pending_buffer: Vec::new(),
        }
    }

    unsafe fn init(&mut self) {
        if self.self_test() {
            rprintln!("Keyboard: self test: ok");
        }
        else {
            rprintln!("Keyboard: self test: failed");
            panic!("Keyboard: self test: failed");
        }

        rprintln!("Keyboard: echo: {}", if self.test_echo() {"ok"} else {"failed"});

        self.disable_scanning();
        self.verify_keyboard();
        self.configure();
        self.enable_scanning();

        self.key_reader.init();
        self.enabled = true;
    }

    pub fn is_enabled(&self) -> bool {
        self.enabled
    }

    /// Waits until output buffer has data
    unsafe fn wait_ready_read(&mut self) {
        loop {
            if (self.status_port.read() & 0x1) != 0 {
                break;
            }
        }
    }

    /// Waits until output buffer has space for data
    unsafe fn wait_ready_write(&mut self) {
        loop {
            if (self.status_port.read() & 0x2) == 0 {
                break;
            }
        }
    }

    pub unsafe fn test_result(&mut self, result: u8) -> bool {
        for _ in 0..IO_WAIT_TIMEOUT {
            io_wait();
            if self.read_byte() == result {
                return true;
            }
        }
        false
    }

    pub unsafe fn test_echo(&mut self) -> bool {
        self.wait_ready_write();
        self.data_port.write(0xEE);
        self.test_result(0xEE)
    }

    pub unsafe fn self_test(&mut self) -> bool {
        self.wait_ready_write();
        self.data_port.write(0xFF);
        self.test_result(0xAA)
    }

    pub unsafe fn verify_keyboard(&mut self) {
        self.wait_ready_write();
        self.data_port.write(0xF2);

        // This doesn't care about ack byte (0xFA), because Qemu doesn't support it, and it's not needed

        for _ in 0..IO_WAIT_TIMEOUT {
            let x = self.read_byte();
            if x == 0xAB {
                for _ in 0..IO_WAIT_TIMEOUT {
                    let kbd_subtype = self.read_byte();
                    if kbd_subtype == 0x41 || kbd_subtype == 0xC1 || kbd_subtype == 0x83 {
                        return;
                    }
                }
                panic!("Unsupported keyboard: unknown subtype");
            }
            io_wait();
        }
        panic!("Unsupported keyboard: cannot identify");
    }

    pub unsafe fn configure(&mut self) {
        // configure PS/2 controller
        self.wait_ready_write();
        self.ps2_write_command(0x20);
        io_wait();
        // https://wiki.osdev.org/%228042%22_PS/2_Controller#PS.2F2_Controller_Configuration_Byte
        let mut conf = self.read_byte();
        conf &= 0b1011_1111; // disable translation
        self.ps2_write_command(0x60);
        self.wait_ready_write();
        self.data_port.write(conf);

        // configure keyboard
        self.wait_ready_write();
        self.data_port.write(0xF0);
        io_wait();
        self.wait_ready_write();
        self.data_port.write(0x02); // scan code set 2
        io_wait();
        if !self.test_result(0xFA) {
            panic!("Unsupported keyboard");
        }
    }

    pub unsafe fn disable_scanning(&mut self) {
        self.wait_ready_write();
        self.data_port.write(0xF5);
        if !self.test_result(0xFA) {
            panic!("Unsupported keyboard");
        }
    }

    pub unsafe fn enable_scanning(&mut self) {
        self.wait_ready_write();
        self.data_port.write(0xF4);
        if !self.test_result(0xFA) {
            panic!("Unsupported keyboard");
        }
    }

    pub unsafe fn notify(&mut self) {
        let key = self.read_byte();
        if !self.enabled || key == 0xFA || key == 0xEE {
            return;
        }
        if let Some(key_event) = self.key_reader.insert(key) {
            self.pending_buffer.push(key_event);
        }
    }

    unsafe fn read_byte(&mut self) -> u8 {
        self.wait_ready_read();
        self.data_port.read()
    }
    unsafe fn ps2_write_command(&mut self, c: u8) {
        self.wait_ready_write();
        self.command_port.write(c)
    }

    pub fn pop_event(&mut self) -> Option<KeyboardEvent> {
        if self.pending_buffer.is_empty() {
            return None;
        }
        Some(self.pending_buffer.remove(0))
    }
}


pub static KEYBOARD: Mutex<Keyboard> = Mutex::new(unsafe { Keyboard::new() });

pub fn init() {
    unsafe {
        // disable interrupts during initialization, so this wont deadlock on not-terribly-slow computers, including Qemu
        asm!("cli"::::"intel","volatile");
        KEYBOARD.lock().init();
        asm!("sti"::::"intel","volatile");
    }
}
