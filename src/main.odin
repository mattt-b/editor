package main


import "core:fmt"
import "core:log"
import "core:os"


import tb "shared:termbox"


main :: proc() {
    if len(os.args) != 2 {
        fmt.print("Usage: ", os.args[0], " <file_to_open>\n");
        os.exit(1);
    }

    fd, err := os.open(os.args[1]);
    if err != 0 {
        fmt.println("Error opening file:", os.args[1]);
        os.exit(1);
    }

    logger_flags := os.O_WRONLY|os.O_CREATE;
    logger_mode := os.S_IRUSR|os.S_IWUSR|os.S_IRGRP|os.S_IWGRP|os.S_IROTH;
    logger_handle, log_err := os.open("editor.log", logger_flags, logger_mode);
    if log_err != 0 {
        fmt.println("Error creating logger");
        os.exit(1);
    }
    context.logger = log.create_file_logger(logger_handle);
    log.info("Editor start");

    buffer := new(Buffer);
    buffer_init(buffer, fd);

    tb_error := tb.init();
    if (cast(int)tb_error != 0) do fmt.print("Could not initialize Termbox: ", tb_error, "\n");

    loop: for {
        buffer.width = cast(int)tb.width();
        buffer.height = cast(int)tb.height();

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

    os.close(fd);
    os.close(logger_handle);
    tb.shutdown();
}
