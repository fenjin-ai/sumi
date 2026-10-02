//! A native test host for the embedded library, not the Tinymist CLI.
unsafe extern "C" {
    fn dup(fd: i32) -> i32;
}

fn main() {
    let input = unsafe { dup(0) };
    let output = unsafe { dup(1) };
    assert!(input >= 0 && output >= 0);
    let status =
        unsafe { leftblank_tinymist::leftblank_tinymist_run(input, output, std::ptr::null()) };
    std::process::exit(status);
}
