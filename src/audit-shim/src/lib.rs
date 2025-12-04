use std::ffi::{CStr, CString};
use std::os::unix::net::UnixStream;
use std::io::Write;
use std::sync::Mutex;
use std::cell::RefCell;
use lazy_static::lazy_static;
use audit_protocol::AuditEvent;
use chrono::Utc;

const DEFAULT_SOCKET_PATH: &str = "/run/containai/audit.sock";

lazy_static! {
    static ref SOCKET_MUTEX: Mutex<()> = Mutex::new(());
    static ref SOCKET_PATH: String = std::env::var("CONTAINAI_SOCKET_PATH")
        .unwrap_or_else(|_| DEFAULT_SOCKET_PATH.to_string());
}

thread_local! {
    static RECURSION_GUARD: RefCell<bool> = RefCell::new(false);
}

fn send_event(event_type: &str, payload: serde_json::Value) {
    // robust recursion protection using thread-local storage
    let recursion_check = RECURSION_GUARD.try_with(|guard| {
        if *guard.borrow() {
            return true;
        }
        *guard.borrow_mut() = true;
        false
    });

    if let Ok(true) | Err(_) = recursion_check {
        return;
    }

    // Ensure we reset the guard even if we panic (which we shouldn't)
    struct GuardReset;
    impl Drop for GuardReset {
        fn drop(&mut self) {
            let _ = RECURSION_GUARD.try_with(|guard| *guard.borrow_mut() = false);
        }
    }
    let _reset = GuardReset;

    // Serialize event before locking to minimize critical section
    let event = AuditEvent {
        timestamp: Utc::now(),
        source: "audit-shim".to_string(),
        event_type: event_type.to_string(),
        payload,
    };

    let json = match serde_json::to_string(&event) {
        Ok(j) => j,
        Err(e) => {
            eprintln!("[audit-shim] Failed to serialize event: {}", e);
            return;
        }
    };

    // Best-effort non-blocking lock to avoid deadlocks in signal handlers or complex scenarios
    let _lock = match SOCKET_MUTEX.try_lock() {
        Ok(g) => g,
        Err(_) => {
            // If we can't get the lock, we drop the event rather than blocking/deadlocking
            return;
        }
    };

    match UnixStream::connect(SOCKET_PATH.as_str()) {
        Ok(mut stream) => {
            if let Err(e) = stream.write_all(json.as_bytes()) {
                eprintln!("[audit-shim] Failed to write to socket: {}", e);
            }
            if let Err(e) = stream.write_all(b"\n") {
                eprintln!("[audit-shim] Failed to write newline: {}", e);
            }
        }
        Err(_e) => {
            // Connection failures are expected if the host is not running
            // We log only on debug builds or if specifically requested to avoid spam
            #[cfg(debug_assertions)]
            eprintln!("[audit-shim] Failed to connect to {}: {}", SOCKET_PATH.as_str(), _e);
        }
    }
}

// Hooking execve
#[no_mangle]
pub unsafe extern "C" fn execve(
    path: *const libc::c_char,
    argv: *const *const libc::c_char,
    envp: *const *const libc::c_char,
) -> libc::c_int {
    // Capture details
    let path_str = CStr::from_ptr(path).to_string_lossy().to_string();
    
    // Collect args
    let mut args = Vec::new();
    if !argv.is_null() {
        let mut ptr = argv;
        while !(*ptr).is_null() {
            args.push(CStr::from_ptr(*ptr).to_string_lossy().to_string());
            ptr = ptr.add(1);
        }
    }

    let payload = serde_json::json!({
        "path": path_str,
        "args": args,
    });

    send_event("execve", payload);

    // Call original
    let original_execve: extern "C" fn(
        *const libc::c_char,
        *const *const libc::c_char,
        *const *const libc::c_char,
    ) -> libc::c_int = std::mem::transmute(libc::dlsym(libc::RTLD_NEXT, CString::new("execve").unwrap().as_ptr()));

    original_execve(path, argv, envp)
}

// Hooking open
#[no_mangle]
pub unsafe extern "C" fn open(path: *const libc::c_char, flags: libc::c_int, mode: libc::mode_t) -> libc::c_int {
     let path_str = CStr::from_ptr(path).to_string_lossy().to_string();
     
     let payload = serde_json::json!({
         "path": path_str,
         "flags": flags,
         "mode": mode
     });

     send_event("open", payload);

    let original_open: extern "C" fn(*const libc::c_char, libc::c_int, libc::mode_t) -> libc::c_int = 
        std::mem::transmute(libc::dlsym(libc::RTLD_NEXT, CString::new("open").unwrap().as_ptr()));

    original_open(path, flags, mode)
}

// Hooking openat
#[no_mangle]
pub unsafe extern "C" fn openat(dirfd: libc::c_int, path: *const libc::c_char, flags: libc::c_int, mode: libc::mode_t) -> libc::c_int {
     let path_str = CStr::from_ptr(path).to_string_lossy().to_string();
     
     let payload = serde_json::json!({
         "dirfd": dirfd,
         "path": path_str,
         "flags": flags,
         "mode": mode
     });

     send_event("openat", payload);

    let original_openat: extern "C" fn(libc::c_int, *const libc::c_char, libc::c_int, libc::mode_t) -> libc::c_int = 
        std::mem::transmute(libc::dlsym(libc::RTLD_NEXT, CString::new("openat").unwrap().as_ptr()));

    original_openat(dirfd, path, flags, mode)
}

// Hooking connect
#[no_mangle]
pub unsafe extern "C" fn connect(
    socket: libc::c_int,
    address: *const libc::sockaddr,
    address_len: libc::socklen_t,
) -> libc::c_int {
    // We could parse the address here, but for now just logging that a connect happened
    let payload = serde_json::json!({
        "fd": socket,
    });
    
    send_event("connect", payload);

    let original_connect: extern "C" fn(libc::c_int, *const libc::sockaddr, libc::socklen_t) -> libc::c_int =
        std::mem::transmute(libc::dlsym(libc::RTLD_NEXT, CString::new("connect").unwrap().as_ptr()));

    original_connect(socket, address, address_len)
}
