package main

import "core:runtime"
import "core:fmt"
import "core:log"
import "core:os"


import tb "shared:termbox"


// Termbox will error when shutdown is called
// when not initialized:
// https://github.com/nsf/termbox/blob/355cccf74f4c7b896ea8a30b318d18d6d199204d/src/termbox.c#L144
_termbox_initialized := false;

assertion_failure_proc :: proc(prefix, message: string, loc: runtime.Source_Code_Location) {
    if _termbox_initialized do tb.shutdown();
    runtime.default_assertion_failure_proc(prefix, message, loc);
}

exit :: proc(status := 0) {
    if _termbox_initialized do tb.shutdown();
    os.exit(status);
}

main :: proc() {
    if len(os.args) != 2 {
        fmt.print_err("Usage: ", os.args[0], " <file_to_open>\n");
        exit(1);
    }
    context.assertion_failure_proc = assertion_failure_proc;

    logger_flags := os.O_WRONLY|os.O_CREATE|os.O_APPEND;
    logger_mode := os.S_IRUSR|os.S_IWUSR|os.S_IRGRP|os.S_IWGRP|os.S_IROTH;
    logger_handle, log_err := os.open("editor.log", logger_flags, logger_mode);
    if log_err != 0 {
        fmt.println_err("Error creating log file");
        exit(1);
    }
    context.logger = log.create_file_logger(logger_handle);
    log.info("\n\n\nEditor start\n\n\n");

    fd, err := os.open(os.args[1], os.O_RDWR);
    if err != 0 {
        fmt.println_err("Error opening file:", os.args[1]);
        exit(1);
    }

    buffer := new(Buffer);
    ok := buffer_init_from_file(buffer, fd);
    if !ok do unimplemented();

    tb_error := tb.init();
    if (int(tb_error) != 0) {
        fmt.print_err("Could not initialize Termbox: ", tb_error, "\n");
        exit(1);
    }
    _termbox_initialized = true;

    for {
        buffer.width = cast(int)tb.width();
        buffer.height = cast(int)tb.height() - 1;

        render_buffer(buffer);

        event : tb.Event;
        tb.poll_event(&event);
        // TODO: Not handling resize/mouse events. Resize will be handled as
        // long as there is only one buffer, but will not work when that code
        // is improved
        if event.kind != tb.EventKind.KEY do continue;
        if event.key == tb.Key.CTRL_C do break;

        buffer_handle_event(buffer, event);
    }

    exit();
}
