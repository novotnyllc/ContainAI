use std::io::{self, ErrorKind, IoSlice, IoSliceMut};
use std::os::fd::{AsRawFd, OwnedFd};

use nix::sys::socket::{self, MsgFlags, Shutdown, UnixAddr};
use serde::Serialize;

use crate::{protocol::AgentTaskRunnerMsgHeader, struct_bytes, struct_bytes_mut, MAX_MESSAGE_SIZE};

/// Convenience wrapper around a Unix seqpacket socket that enforces the
/// Agent Task Runner framing rules.
pub struct SeqPacketChannel {
    fd: OwnedFd,
}

impl SeqPacketChannel {
    /// Creates a channel from an owned file descriptor.
    pub fn new(fd: OwnedFd) -> Self {
        Self { fd }
    }

    /// Provides another handle to the same socket so different threads can
    /// stream concurrently.
    pub fn try_clone(&self) -> io::Result<Self> {
        Ok(Self {
            fd: self.fd.try_clone()?,
        })
    }

    /// Receives a single framed message. Returns `Ok(None)` if the peer has
    /// closed its write side.
    pub fn recv_message(&self) -> io::Result<Option<(AgentTaskRunnerMsgHeader, Vec<u8>)>> {
        let mut header = AgentTaskRunnerMsgHeader::new(0, 0);
        let mut payload_buf = vec![0u8; MAX_MESSAGE_SIZE];
        let mut iov = [
            IoSliceMut::new(struct_bytes_mut(&mut header)),
            IoSliceMut::new(&mut payload_buf),
        ];
        let msg =
            socket::recvmsg::<UnixAddr>(self.fd.as_raw_fd(), &mut iov, None, MsgFlags::empty())
                .map_err(nix_to_io)?;
        if msg.bytes == 0 {
            return Ok(None);
        }
        if msg.bytes < std::mem::size_of::<AgentTaskRunnerMsgHeader>() {
            return Err(io::Error::new(
                ErrorKind::UnexpectedEof,
                "message shorter than header",
            ));
        }
        if msg.flags.contains(MsgFlags::MSG_TRUNC) {
            return Err(io::Error::new(ErrorKind::InvalidData, "message truncated"));
        }
        let payload_len = msg.bytes - std::mem::size_of::<AgentTaskRunnerMsgHeader>();
        payload_buf.truncate(payload_len);
        if header.length as usize != payload_len {
            return Err(io::Error::new(
                ErrorKind::InvalidData,
                "header length mismatch",
            ));
        }
        Ok(Some((header, payload_buf)))
    }

    /// Sends a header + payload pair, enforcing the maximum payload length and
    /// propagating any socket errors.
    pub fn send_message(&self, msg_type: u32, payload: &[u8]) -> io::Result<()> {
        if payload.len() > u32::MAX as usize {
            return Err(io::Error::new(ErrorKind::InvalidData, "payload too large"));
        }
        let header = AgentTaskRunnerMsgHeader::new(msg_type, payload.len() as u32);
        let iov = [IoSlice::new(struct_bytes(&header)), IoSlice::new(payload)];
        socket::sendmsg::<UnixAddr>(self.fd.as_raw_fd(), &iov, &[], MsgFlags::empty(), None)
            .map_err(nix_to_io)?;
        Ok(())
    }

    /// Serializes the provided value as JSON and ships it as a payload.
    pub fn send_json<T: Serialize>(&self, msg_type: u32, value: &T) -> io::Result<()> {
        let payload =
            serde_json::to_vec(value).map_err(|err| io::Error::new(ErrorKind::InvalidData, err))?;
        self.send_message(msg_type, &payload)
    }

    /// Shuts down the read half of the socket to wake any blocking readers.
    pub fn shutdown_read(&self) -> io::Result<()> {
        socket::shutdown(self.fd.as_raw_fd(), Shutdown::Read).map_err(nix_to_io)
    }

    /// Returns the underlying file descriptor for use with lower-level APIs.
    pub fn into_inner(self) -> OwnedFd {
        self.fd
    }
}

/// Converts a `nix` socket error into a stable `io::Error` surface.
fn nix_to_io(err: nix::Error) -> io::Error {
    io::Error::other(err.to_string())
}
