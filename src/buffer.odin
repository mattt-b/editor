package main

import "core:fmt"
import "core:os"

import tb "shared:termbox"

import "util"


BufferMode :: enum u8 {
    Normal,
    Insert,
}


Cursor :: struct {
    char: int,
    line: int,
    // Used when char has to be lowered while moving up and down.
    // Example: line=1 has 10 chars and char is 8. line=2 has 3 chars.
    // When moving from line=1 to line=2, the char will be set to 2.
    // When moving back to line=1 this is used to set char back to 7.
    prev_char: int,
}


Buffer :: struct {
    width: int,
    height: int,

    top_line: int,

    // TODO: Rename this whatever it's called in vim/emacs
    // Number of lines before the top or bottom of the screen to start shifting
    // top_line.
    // In a 50 line file, with a buffer height of 10, and a scroll_off of 2
    // moving down on line 8 would change the top_line to 1.
    scroll_off: int,

    mode: BufferMode,
    text: ^Text,
    cursor: Cursor,
}


buffer_init_from_file :: proc(using buf: ^Buffer, fd: os.Handle) -> bool #require_results {
    buf.mode = .Normal;
    buf.scroll_off = 5;

    text = new(Text);
    if buf.text == nil do return false;

    file_size, err := os.file_size(fd);
    if err != 0 {
        fmt.println_err("Error reading file");
        unimplemented();
    }
    file_data := make([]u8, file_size);
    _, err = os.read(fd, file_data);
    if err != 0 {
        fmt.println_err("Error reading file");
        unimplemented();
    }
    defer(delete(file_data));

    ok := text_init(buf.text, file_data, fd);
    if !ok do unimplemented();

    return true;
}


buffer_handle_event_insert :: proc(buffer: ^Buffer, event: tb.Event) {
    if event.ch != 0 {
        ok := text_insert(buffer.text, event.ch, buffer.cursor.line, buffer.cursor.char);
        if !ok do unimplemented();

        buffer.cursor.char += 1;
        buffer.cursor.prev_char = buffer.cursor.char;
        return;
    }

    switch event.key {
    case tb.Key.SPACE:
        ok := text_insert(buffer.text, ' ', buffer.cursor.line, buffer.cursor.char);
        if !ok do unimplemented();

        buffer.cursor.char += 1;
        buffer.cursor.prev_char = buffer.cursor.char;

    case tb.Key.TAB:
        ok := text_insert(buffer.text, '\t', buffer.cursor.line, buffer.cursor.char);
        if !ok do unimplemented();

        buffer.cursor.char += 1;
        buffer.cursor.prev_char = buffer.cursor.char;

    case tb.Key.ENTER:
        ok := text_insert_newline(buffer.text, buffer.cursor.line, buffer.cursor.char);
        if !ok do  unimplemented();

        buffer.cursor.line += 1;
        buffer.cursor.char = 0;
        buffer.cursor.prev_char = buffer.cursor.char;

    case tb.Key.BACKSPACE: fallthrough;
    case tb.Key.BACKSPACE2:
        line_num := buffer.cursor.line;
        char := buffer.cursor.char;
        if line_num == 0 && char == 0 do return;

        if char != 0 {
            buffer.cursor.char -= 1;
        } else {
            assert(line_num != 0);
            // backspacing newline
            prev_line := buffer.text.lines[line_num - 1];
            buffer.cursor.line -= 1;
            buffer.cursor.char = prev_line.char_count;
        }
        buffer.cursor.prev_char = buffer.cursor.char;

        text_backspace(buffer.text, line_num, char);

    case tb.Key.DELETE:
        text_delete(buffer.text, buffer.cursor.line, buffer.cursor.char);

    case tb.Key.CTRL_S:
        ok := buffer_save(buffer);
        if !ok do unimplemented();
        fallthrough;
    case tb.Key.ESC:
        buffer.mode = BufferMode.Normal;
        buffer.cursor.char = max(0, buffer.cursor.char - 1);
        buffer.cursor.prev_char = buffer.cursor.char;
        text_end_change(buffer.text);
    }
}


buffer_handle_event_normal :: proc(buffer: ^Buffer, event: tb.Event) {
    switch event.ch {
    case 0: break; // event.ch == 0 when event.key is set instead
    case 'i':
        text_begin_change(buffer.text, buffer.cursor.line, buffer.cursor.char);
        buffer.mode = BufferMode.Insert;

    case 'a':
        if buffer.text.lines[buffer.cursor.line].char_count != 0 {
            buffer.cursor.char += 1;
        }
        buffer.cursor.prev_char = buffer.cursor.char;

        text_begin_change(buffer.text, buffer.cursor.line, buffer.cursor.char);
        buffer.mode = BufferMode.Insert;
    case 'A':
        buffer.cursor.char = buffer.text.lines[buffer.cursor.line].char_count;
        buffer.cursor.prev_char = buffer.cursor.char;

        text_begin_change(buffer.text, buffer.cursor.line, buffer.cursor.char);
        buffer.mode = BufferMode.Insert;

    case 'x':
        text_begin_change(buffer.text, buffer.cursor.line, buffer.cursor.char);
        text_delete(buffer.text, buffer.cursor.line, buffer.cursor.char);
        text_end_change(buffer.text);

        line := buffer.text.lines[buffer.cursor.line];
        if buffer.cursor.char >= line.char_count {
            buffer.cursor.char = max(line.char_count - 1, 0);
        }

    case 'u':
        if len(buffer.text.past_changes) > 0 {
            change := buffer.text.past_changes[len(buffer.text.past_changes) - 1];
            buffer_move_cursor(buffer, change.cursor_line, change.cursor_char);
            ok := text_undo(buffer.text);
            if !ok do unimplemented();
        }

    case 'h':
        buffer_move_cursor(buffer, Direction.Left);
    case 'j':
        buffer_move_cursor(buffer, Direction.Down);
    case 'k':
        buffer_move_cursor(buffer, Direction.Up);
    case 'l':
        buffer_move_cursor(buffer, Direction.Right);

    case '0':
        buffer.cursor.char = 0;
        buffer.cursor.prev_char = 0;
    case '$':
        buffer.cursor.char = max(buffer.text.lines[buffer.cursor.line].char_count - 1, 0);
        buffer.cursor.prev_char = max(int);

    case 'G':
        buffer_move_cursor(buffer, len(buffer.text.lines) - 1);
    }

    switch event.key {
    case .CTRL_S:
        ok := buffer_save(buffer);
        if !ok do unimplemented();

    // TODO: These do not behave the same as Vim. Vim moves the text area by N lines,
    // this is moving the cursor. Decide which version is preferrable.
    case .CTRL_D:
        destination := min(buffer.cursor.line + 30, len(buffer.text.lines) - 1);
        buffer_move_cursor(buffer, destination);
    case .CTRL_U:
        destination := max(buffer.cursor.line - 30, 0);
        buffer_move_cursor(buffer, destination);

    case .CTRL_R:
        if len(buffer.text.future_changes) > 0 {
            change := buffer.text.future_changes[len(buffer.text.future_changes) - 1];
            char := line_char(buffer.text.lines[change.line], change.index);
            buffer_move_cursor(buffer, change.line, char);
            ok := text_redo(buffer.text);
            if !ok do unimplemented();
        }
    }

}


buffer_handle_event :: proc(buffer: ^Buffer, event: tb.Event) {
    switch buffer.mode {
    case .Normal:
        buffer_handle_event_normal(buffer, event);
    case .Insert:
        buffer_handle_event_insert(buffer, event);
    }
}


Direction :: enum u8 {
    Up,
    Down,
    Left,
    Right,
}


buffer_move_cursor_direction :: proc(using buffer: ^Buffer, direction: Direction) {
    #complete switch direction {
    case .Up:
        cursor.line = max(0, cursor.line - 1);
        line := text.lines[cursor.line];
        cursor.char = line.char_count == 0 ? 0 : min(cursor.prev_char, line.char_count - 1);

        if cursor.line < buffer.scroll_off + buffer.top_line {
            buffer.top_line = max(buffer.top_line - 1, 0);
        }

    case .Down:
        cursor.line = min(len(buffer.text.lines) - 1, cursor.line + 1);
        line := text.lines[cursor.line];
        cursor.char = line.char_count == 0 ? 0 : min(cursor.prev_char, line.char_count - 1);

        if cursor.line < len(text.lines) - 1 {
            // every line up to the last line, scroll when hitting the offset
            if cursor.line - buffer.top_line > buffer.height - 1 - buffer.scroll_off do buffer.top_line += 1;
        } else {
            // allow last line to scroll to top of page
            if buffer.top_line < len(text.lines) - 1 do buffer.top_line += 1;
        }

    case .Left:
        cursor.char = max(0, cursor.char - 1);
        cursor.prev_char = cursor.char;

    case .Right:
        line := text.lines[cursor.line];
        cursor.char = line.char_count == 0 ? 0 : min(cursor.char + 1, line.char_count - 1);
        cursor.prev_char = cursor.char;
    }
}

buffer_move_cursor_line_char :: proc(buffer: ^Buffer, line: int, char: int) {
    /* destination_is_visible := line >= buffer.top_line && line <= buffer.height + buffer.top_line; */
    if line < buffer.top_line {
        if line < buffer.scroll_off {
            buffer.top_line = 0;
        } else {
            // TODO: need to handle when buffer.height gets too small
            // (not here, handle during resize events)
            buffer.top_line = line - buffer.scroll_off;
        }
    } else if line > buffer.height + buffer.top_line {
        buffer.top_line = line - buffer.height + buffer.scroll_off;
    }

    buffer.cursor.line = line;
    buffer.cursor.char = char;
    buffer.cursor.prev_char = char;
}

buffer_move_cursor_line :: proc(buffer: ^Buffer, line_num: int) {
    line := buffer.text.lines[line_num];
    char_num := line.char_count == 0 ? 0 : min(buffer.cursor.prev_char, line.char_count - 1);
    buffer_move_cursor(buffer, line_num, char_num);
}

buffer_move_cursor :: proc{buffer_move_cursor_direction, buffer_move_cursor_line_char,
                          buffer_move_cursor_line};


render_buffer :: proc(buffer: ^Buffer) {
    row := 0;
    for ; row < (len(buffer.text.lines) - buffer.top_line) && row < buffer.height; row += 1 {
        col := 0;
        for char in string(buffer.text.lines[row + buffer.top_line].content[:]) {
            switch {
            case char >= 256:
                // utf8 char
                // assumed to only take one displayable char
                fallthrough;
            case char >= DISPLAYABLE_ASCII_MIN && char <= DISPLAYABLE_ASCII_MAX:
                // single cell ascii char
                tb.change_cell(i32(col), i32(row), char,
                               tb.Color.DEFAULT, tb.Color.DEFAULT);
                col += 1;
            case char == '\t':
                for _ in 1..buffer.text.tab_width {
                    tb.change_cell(i32(col), i32(row), rune(' '),
                                   tb.Color.DEFAULT, tb.Color.DEFAULT);
                    col += 1;
                }
            case:
                // multi cell ascii escape code
                display_str := AsciiDisplayTable[char];
                for display_char in display_str {
                    tb.change_cell(i32(col), i32(row), display_char,
                                   tb.Color.DEFAULT, tb.Color.DEFAULT);
                    col += 1;
                }
            }

            if col > buffer.width do break;
        }
        for ; col < buffer.width; col += 1 {
            tb.change_cell(i32(col), i32(row), rune(' '),
                           tb.Color.DEFAULT, tb.Color.DEFAULT);
        }
    }
    // TODO: just set this memory instead of iterating
    for ; row < buffer.height; row += 1 {
        for col := 0; col < buffer.width; col += 1 {
            tb.change_cell(i32(col), i32(row), rune(' '),
                           tb.Color.DEFAULT, tb.Color.DEFAULT);
        }
    }

    // Status Bar
    mode_display: rune;
    mode_color: tb.Color;
    #complete switch buffer.mode {
        case .Normal:
            mode_display = 'N';
            mode_color = .BLUE;
        case .Insert:
            mode_display = 'I';
            mode_color = .GREEN;
    }
    tb.change_cell(0, i32(buffer.height), mode_display,
                   tb.Color.WHITE | tb.Color.BOLD, mode_color);
    for i := 1; i < buffer.width; i += 1 {
        tb.change_cell(i32(i), i32(buffer.height), ' ',
                       tb.Color.WHITE | tb.Color.BOLD, mode_color);
    }

    cursor_line := buffer.text.lines[buffer.cursor.line];
    cursor_display_col := 0;
    for char, i in string(cursor_line.content[:]) {
        if i == buffer.cursor.char do break;
        cursor_display_col += char_display_len(char, buffer.text.tab_width);
    }

    tb.set_cursor(i32(cursor_display_col), i32(buffer.cursor.line - buffer.top_line));

    tb.present();
}


buffer_save :: proc(buffer: ^Buffer) -> bool #require_results {
    // TODO: This needs improvements and won't work on windows

    if buffer.text.fd == os.INVALID_HANDLE do unimplemented();

    file_data: [dynamic]u8;
    defer(delete(file_data));

    for line in buffer.text.lines {
        append(&file_data, ..line.content[:]);
        #complete switch buffer.text.line_end_style {
            case .LF: append(&file_data, '\n');
            case .CRLF: append(&file_data, '\r', '\n');
        }
    }

    err: os.Errno;
    _, err = os.seek(buffer.text.fd, 0, os.SEEK_SET);
    if err != os.ERROR_NONE do return false;
    err = util.fd_truncate(buffer.text.fd, len(file_data));
    if err != os.ERROR_NONE do return false;
    _, err = os.write(buffer.text.fd, file_data[:]);
    if err != os.ERROR_NONE do return false;
    return true;
}
