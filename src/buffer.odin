package main

import "core:os"
import "core:unicode/utf8"

import tb "shared:termbox"


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
    x: int,
    line: int,
    // Used when x has to be lowered while moving up and down.
    // Example: line=1 has 10 chars and x is 8. line=2 has 3 chars.
    // When moving from line=1 to line=2, the x will be set to 2.
    // When moving back to line=1 this is used to set x back to 7.
    prev_x: int,
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

        buffer.cursor.x += char_display_len(event.ch, buffer.text.tab_width);
        buffer.cursor.prev_x = buffer.cursor.x;
        return;
    }

    switch event.key {
    case tb.Key.SPACE:
        ok := text_insert(buffer.text, ' ');
        if !ok do unimplemented();

        buffer.cursor.x += 1;
        buffer.cursor.prev_x = buffer.cursor.x;

    case tb.Key.TAB:
        ok := text_insert(buffer.text, '\t');
        if !ok do unimplemented();

        buffer.cursor.x += buffer.text.tab_width;
        buffer.cursor.prev_x = buffer.cursor.x;

    case tb.Key.ENTER: fallthrough;
    case tb.Key.BACKSPACE: fallthrough;
    case tb.Key.BACKSPACE2: fallthrough;
    case tb.Key.DELETE: unimplemented();

    case tb.Key.ESC:
        buffer.mode = BufferMode.Normal;
        buffer.cursor.x = max(0, buffer.cursor.x - 1);
        buffer.cursor.prev_x = buffer.cursor.x;
    }
}


import "core:log"
buffer_handle_event_normal :: proc(buffer: ^Buffer, event: tb.Event) {
    switch {
    case event.ch == 'i':
        text_begin_insert(buffer.text, buffer.cursor.line, buffer.cursor.x);
        buffer.mode = BufferMode.Insert;

    case event.ch == 'h':
        buffer_move_cursor(buffer, Direction.Left);
    case event.ch == 'j':
        buffer_move_cursor(buffer, Direction.Down);
    case event.ch == 'k':
        buffer_move_cursor(buffer, Direction.Up);
    case event.ch == 'l':
        buffer_move_cursor(buffer, Direction.Right);

    case event.ch == '0':
        buffer.cursor.x = 0;
        buffer.cursor.prev_x = 0;
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
    // Handle multichar chars (tab/escape codes)
    x_fix :: proc(line: Line, attempt_col: int, tab_width: int) -> int {
        // Whether these are valid is handled elsewhere
        assert(attempt_col < line.display_len ||
               (line.display_len == 0 && attempt_col == 0));

        if len(line.content) == line.display_len {
            return attempt_col;
        }

        // TODO: This will linearly walk the line and calculate the proper
        // cursor position so it can only land on the first column of a
        // multi column character. Could keep track of the difference
        // between the len(line.content) - line.display_len vs the multi
        // column chars seen so far and move to an absolute position once
        // it is known that there are no more multi column chars in the line.
        // This will probably be the most common case - a single tab - cutting
        // the linear search off immediately.
        // This can probably be done in a number of locations where we check
        // 'if len(line.content) == line.display_len'
        // All of this could be further simplified if cursor space referred
        // to rune index into a line instead of screen space
        prev_col := 0;
        cur_col := prev_col;
        bytes_read := 0;
        for cur_col < attempt_col {
            prev_col = cur_col;
            char, rune_len := utf8.decode_rune(line.content[bytes_read:]);
            bytes_read += rune_len;

            cur_col += char_display_len(char, tab_width);
        }
        // Last char isn't a multichar, no reason to backtrack
        if cur_col == prev_col + 1 {
            return cur_col;
        }

        if cur_col >= line.display_len {
            return prev_col;
        } else {
            return cur_col;
        }
    }

    #complete switch direction {
    case .Up:
        cursor.line = max(0, cursor.line - 1);

        if cursor.line < buffer.scroll_off + buffer.y_off {
            buffer.y_off = max(buffer.y_off - 1, 0);
        }

        line := text.lines[cursor.line];
        line_len := line.display_len;
        max_x := max(line_len - 1, 0);
        cursor.x = x_fix(line, min(max_x, cursor.prev_x), text.tab_width);

    case .Down:
        cursor.line = min(len(buffer.text.lines) - 1, cursor.line + 1);

        if cursor.line < len(text.lines) - 1 {
            // every line up to the last line, scroll when hitting the offset
            if cursor.line - buffer.y_off > buffer.height - 1 - buffer.scroll_off do buffer.y_off += 1;
        } else {
            // allow last line to scroll to top of page
            if buffer.y_off < len(text.lines) - 1 do buffer.y_off += 1;
        }

        line := text.lines[cursor.line];
        line_len := line.display_len;
        max_x := max(line_len - 1, 0);
        cursor.x = x_fix(line, min(max_x, cursor.prev_x), text.tab_width);

    case .Left:
        line := text.lines[cursor.line];
        if len(line.content) == line.display_len {
            cursor.x = max(0, cursor.x - 1);
        } else {
            desired_col := max(0, cursor.x - 1);
            prev_col := 0;
            cur_col := prev_col;
            bytes_read := 0;
            for cur_col <= desired_col {
                prev_col = cur_col;

                char, rune_len := utf8.decode_rune(line.content[bytes_read:]);
                bytes_read += rune_len;

                cur_col += char_display_len(char, text.tab_width);
            }
            if cur_col == desired_col {
                cursor.x = cur_col;
            } else {
                cursor.x = prev_col;
            }
        }
        cursor.prev_x = cursor.x;

    case .Right:
        line := text.lines[cursor.line];
        line_len := line.display_len;
        if line_len == 0 {
            cursor.x = 0;
        } else {
            cursor.x = x_fix(line, min(line_len - 1, cursor.x + 1), text.tab_width);
        }
        cursor.prev_x = cursor.x;
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

    tb.set_cursor(cast(i32)buffer.cursor.x, i32(buffer.cursor.line - buffer.y_off));
    tb.present();
}
