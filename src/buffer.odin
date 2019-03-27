package main

import "core:os"

import tb "shared:termbox"

import "util"


BufferMode :: enum u8 {
    Normal,
    Insert,
}


Cursor :: struct {
    // TODO:
    // x is column in a line. It is essentially equivalent to
    // where in the 'count' of unicode 'rune's it is on the line.
    // It would be good to change this to directly refer to that,
    // but I need to think more about how to reconcile that with
    // empty lines (easy) and appending to the end of a line (less easy).
    // If this could be changed, most places that refer to 'display_len'
    // wouldn't need to anymore
    char: int,
    line: int,
    // Used when x has to be lowered while moving up and down.
    // Example: line=1 has 10 chars and x is 8. line=2 has 3 chars.
    // When moving from line=1 to line=2, the x will be set to 2.
    // When moving back to line=1 this is used to set x back to 7.
    prev_char: int,
}


Buffer :: struct {
    width: int,
    height: int,
    // Lines shifted from the first line to display at the top of the buffer
    y_off: int,

    // TODO: Rename this whatever it's called in vim/emacs
    // Number of lines before the top or bottom of the screen to start shifting
    // y_off.
    // In a 50 line file, with a buffer height of 10, and a scroll_off of 2
    // moving down on line 8 would change the y_off to 1.
    scroll_off: int,

    mode: BufferMode,
    text: ^Text,
    cursor: Cursor,
}


buffer_init :: proc(buf: ^Buffer, fd: os.Handle) -> bool #require_results {
    buf.mode = BufferMode.Normal;
    buf.scroll_off = 5;

    buf.text = new(Text);
    if buf.text == nil do return false;
    ok := text_init(buf.text, fd);
    if !ok do unimplemented();
    return true;
}


buffer_handle_event_insert :: proc(buffer: ^Buffer, event: tb.Event) {
    if event.ch != 0 {
        ok := text_insert(buffer.text, event.ch);
        if !ok do unimplemented();

        buffer.cursor.char += 1;
        buffer.cursor.prev_char = buffer.cursor.char;
        return;
    }

    switch event.key {
    case tb.Key.SPACE:
        ok := text_insert(buffer.text, ' ');
        if !ok do unimplemented();

        buffer.cursor.char += 1;
        buffer.cursor.prev_char = buffer.cursor.char;

    case tb.Key.TAB:
        ok := text_insert(buffer.text, '\t');
        if !ok do unimplemented();

        buffer.cursor.char += 1;
        buffer.cursor.prev_char = buffer.cursor.char;

    case tb.Key.ENTER: fallthrough;
    case tb.Key.BACKSPACE: fallthrough;
    case tb.Key.BACKSPACE2: unimplemented();
    case tb.Key.DELETE:
        text_delete(buffer.text);

    case tb.Key.CTRL_S:
        ok := buffer_save(buffer);
        if !ok do unimplemented();
        fallthrough;
    case tb.Key.ESC:
        buffer.mode = BufferMode.Normal;
        buffer.cursor.char = max(0, buffer.cursor.char - 1);
        buffer.cursor.prev_char = buffer.cursor.char;
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
        text_delete(buffer.text);
        line := buffer.text.lines[buffer.cursor.line];
        if buffer.cursor.char >= line.char_count {
            buffer.cursor.char = max(line.char_count - 1, 0);
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

    }

    switch event.key {
    case tb.Key.CTRL_S:
        ok := buffer_save(buffer);
        if !ok do unimplemented();
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


buffer_move_cursor :: proc(using buffer: ^Buffer, direction: Direction) {
    #complete switch direction {
    case .Up:
        cursor.line = max(0, cursor.line - 1);

        line := text.lines[cursor.line];
        cursor.char = line.char_count == 0 ? 0 : min(cursor.prev_char, line.char_count - 1);

        if cursor.line < buffer.scroll_off + buffer.y_off {
            buffer.y_off = max(buffer.y_off - 1, 0);
        }

    case .Down:
        cursor.line = min(len(buffer.text.lines) - 1, cursor.line + 1);
        line := text.lines[cursor.line];
        cursor.char = line.char_count == 0 ? 0 : min(cursor.prev_char, line.char_count - 1);

        if cursor.line < len(text.lines) - 1 {
            // every line up to the last line, scroll when hitting the offset
            if cursor.line - buffer.y_off > buffer.height - 1 - buffer.scroll_off do buffer.y_off += 1;
        } else {
            // allow last line to scroll to top of page
            if buffer.y_off < len(text.lines) - 1 do buffer.y_off += 1;
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


render_buffer :: proc(buffer: ^Buffer) {
    row := 0;
    for ; row < (len(buffer.text.lines) - buffer.y_off) && row < buffer.height; row += 1 {
        col := 0;
        for char in string(buffer.text.lines[row + buffer.y_off].content[:]) {
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

    tb.set_cursor(i32(cursor_display_col), i32(buffer.cursor.line - buffer.y_off));

    tb.present();
}


buffer_save :: proc(buffer: ^Buffer) -> bool #require_results {
    // TODO: This needs improvements and won't work on windows
    file_data: [dynamic]u8;
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
