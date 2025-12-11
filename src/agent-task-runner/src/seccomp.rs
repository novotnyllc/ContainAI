use std::io;
use std::os::fd::RawFd;

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct SeccompData {
    pub nr: i32,
    pub arch: u32,
    pub instruction_pointer: u64,
    pub args: [u64; 6],
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct SeccompNotif {
    pub id: u64,
    pub pid: u32,
    pub flags: u32,
    pub data: SeccompData,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct SeccompNotifResp {
    pub id: u64,
    pub val: i64,
    pub error: i32,
    pub flags: u32,
}

const SECCOMP_IOC_MAGIC: u8 = b'!';

const SECCOMP_IOCTL_NOTIF_RECV: libc::c_ulong =
    nix::request_code_readwrite!(SECCOMP_IOC_MAGIC, 0, ::core::mem::size_of::<SeccompNotif>())
        as libc::c_ulong;
const SECCOMP_IOCTL_NOTIF_SEND: libc::c_ulong = nix::request_code_readwrite!(
    SECCOMP_IOC_MAGIC,
    1,
    ::core::mem::size_of::<SeccompNotifResp>()
) as libc::c_ulong;

pub const SECCOMP_USER_NOTIF_FLAG_CONTINUE: u32 = 1;

pub fn recv_notification(fd: RawFd, req: &mut SeccompNotif) -> io::Result<()> {
    let rc = unsafe {
        libc::ioctl(
            fd,
            SECCOMP_IOCTL_NOTIF_RECV,
            req as *mut _ as *mut libc::c_void,
        )
    };
    if rc == 0 {
        Ok(())
    } else {
        Err(io::Error::last_os_error())
    }
}

pub fn send_response(fd: RawFd, resp: &mut SeccompNotifResp) -> io::Result<()> {
    let rc = unsafe {
        libc::ioctl(
            fd,
            SECCOMP_IOCTL_NOTIF_SEND,
            resp as *mut _ as *mut libc::c_void,
        )
    };
    if rc == 0 {
        Ok(())
    } else {
        Err(io::Error::last_os_error())
    }
}
