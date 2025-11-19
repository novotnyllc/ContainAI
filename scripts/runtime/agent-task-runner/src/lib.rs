//! Lightweight protocol helpers shared by the runner daemon, sandbox helper,
//! CLI shim, and client binaries.

pub mod channel;
pub mod seccomp;

/// Default filesystem location for the runner's seqpacket socket.
pub const DEFAULT_SOCKET_PATH: &str = "/run/agent-task-runner.sock";
/// Maximum bytes we ever read or write per protocol frame.
pub const MAX_MESSAGE_SIZE: usize = 128 * 1024;

pub mod protocol {
    /// Protocol version embedded in registration payloads so the daemon can
    /// reject incompatible clients.
    pub const PROTOCOL_VERSION: u32 = 1;
    pub const MSG_REGISTER: u32 = 1;
    pub const MSG_RUN_REQUEST: u32 = 2;
    pub const MSG_RUN_STDIN: u32 = 3;
    pub const MSG_RUN_STDIN_CLOSE: u32 = 4;
    pub const MSG_RUN_STDOUT: u32 = 100;
    pub const MSG_RUN_STDERR: u32 = 101;
    pub const MSG_RUN_EXIT: u32 = 102;
    pub const MSG_RUN_ERROR: u32 = 103;
    pub const MSG_RUN_STARTED: u32 = 104;
    pub const AGENT_NAME_LEN: usize = 32;
    pub const BINARY_NAME_LEN: usize = 128;

    #[repr(C)]
    #[derive(Clone, Copy)]
    pub struct AgentTaskRunnerMsgHeader {
        pub msg_type: u32,
        pub reserved: u32,
        pub length: u32,
    }

    impl AgentTaskRunnerMsgHeader {
        /// Helper constructor that zeroes the reserved field and stores a
        /// payload length.
        pub const fn new(msg_type: u32, length: u32) -> Self {
            Self {
                msg_type,
                reserved: 0,
                length,
            }
        }
    }

    #[repr(C)]
    #[derive(Clone, Copy)]
    pub struct AgentTaskRunnerRegister {
        pub version: u32,
        pub pid: u32,
        pub agent_name: [u8; AGENT_NAME_LEN],
        pub binary_name: [u8; BINARY_NAME_LEN],
    }

    impl AgentTaskRunnerRegister {
        /// Creates an empty registration buffer that callers can later fill in
        /// with process metadata before sending.
        pub const fn empty() -> Self {
            Self {
                version: PROTOCOL_VERSION,
                pid: 0,
                agent_name: [0; AGENT_NAME_LEN],
                binary_name: [0; BINARY_NAME_LEN],
            }
        }
    }
}

/// Writes a string into a fixed-size C buffer, ensuring truncation and
/// null-termination while falling back to a default label when needed.
pub fn write_cstring_buf(buf: &mut [u8], value: Option<&str>, fallback: &str) {
    let trimmed = match value {
        Some(val) if !val.is_empty() => val,
        _ if !fallback.is_empty() => fallback,
        _ => "unknown",
    };
    let bytes = trimmed.as_bytes();
    let copy_len = bytes.len().min(buf.len().saturating_sub(1));
    buf.fill(0);
    buf[..copy_len].copy_from_slice(&bytes[..copy_len]);
}

/// Returns a byte slice view of any Pod-style structure.
pub fn struct_bytes<T>(value: &T) -> &[u8] {
    unsafe {
        core::slice::from_raw_parts((value as *const T) as *const u8, core::mem::size_of::<T>())
    }
}

/// Returns a mutable byte slice view of any Pod-style structure.
pub fn struct_bytes_mut<T>(value: &mut T) -> &mut [u8] {
    unsafe {
        core::slice::from_raw_parts_mut((value as *mut T) as *mut u8, core::mem::size_of::<T>())
    }
}

#[cfg(test)]
mod tests {
    use super::{
        protocol::AgentTaskRunnerMsgHeader, struct_bytes, struct_bytes_mut, write_cstring_buf,
    };

    #[test]
    fn write_cstring_buf_uses_fallback_when_value_missing() {
        let mut buf = [0u8; 8];
        write_cstring_buf(&mut buf, None, "runner");
        assert_eq!(b"runner\0\0", &buf);
    }

    #[test]
    fn write_cstring_buf_truncates_and_null_terminates() {
        let mut buf = [0u8; 5];
        write_cstring_buf(&mut buf, Some("longer-than-buf"), "");
        assert_eq!(b"long\0", &buf);
    }

    #[test]
    fn struct_bytes_reflects_struct_layout() {
        let header = AgentTaskRunnerMsgHeader::new(1, 16);
        let bytes = struct_bytes(&header);
        assert_eq!(
            core::mem::size_of::<AgentTaskRunnerMsgHeader>(),
            bytes.len()
        );

        let mut header_mut = AgentTaskRunnerMsgHeader::new(2, 8);
        let bytes_mut = struct_bytes_mut(&mut header_mut);
        assert_eq!(
            core::mem::size_of::<AgentTaskRunnerMsgHeader>(),
            bytes_mut.len()
        );
        bytes_mut.copy_from_slice(&bytes);
        let msg_type =
            unsafe { core::ptr::read_unaligned(core::ptr::addr_of!(header_mut.msg_type)) };
        let length = unsafe { core::ptr::read_unaligned(core::ptr::addr_of!(header_mut.length)) };
        assert_eq!(msg_type, 1);
        assert_eq!(length, 16);
    }
}
