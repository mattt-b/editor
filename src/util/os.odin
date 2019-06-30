package util

import "core:os"

foreign import libc "system:c"


foreign libc {
    @(link_name="ftruncate") _unix_ftruncate :: proc(fd: os.Handle, length: int) -> int ---;
}


fd_truncate :: proc(fd: os.Handle, length: int) -> os.Errno {
    result := _unix_ftruncate(fd, length);
    if result == -1 do return os.Errno(os.get_last_error());
    return os.ERROR_NONE;
}

truncate :: proc{fd_truncate};
