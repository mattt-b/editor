package main

import "core:os"
import "core:unicode/utf8"

import tb "shared:termbox"


BufferMode :: enum u8 {
    Normal,
    Insert,
}


Cursor :: struct {
    x: int,
    y: int,
    // Used when x has to be lowered while moving up and down.
    // Example: line y=1 has 10 chars and x is 8. Line y=2 has 3 chars.
    // When moving from y=1 to y=2, the x will be set to 3.
    // When moving back to y=1 this is used to set x back to 8.
    prev_x: int,
}


Buffer :: struct {
    width: int,
    height: int,
    mode: BufferMode,
    text: ^Text,
    cursor: Cursor,
}


buffer_init :: proc(buf: ^Buffer, fd: os.Handle) -> bool #require_results {
    buf.mode = BufferMode.Normal;
    buf.cursor.x = 1;
    buf.cursor.y = 1;
    buf.cursor.prev_x = 1;
    buf.text = new(Text);
    if buf.text == nil do return false;
    ok := text_init(buf.text, fd);
    if !ok do unimplemented();
    return true;
}


buffer_handle_event_insert :: proc(buffer: ^Buffer, event: tb.Event) {
    switch {
    case event.ch != 0:
        ok := text_insert(buffer.text, event.ch);
        if !ok do unimplemented();

        // TODO: this won't handle cursor movement on multi-chars
        buffer.cursor.x += 1;
        buffer.cursor.prev_x = buffer.cursor.x;

    case event.key == tb.Key.ESC:
        buffer.mode = BufferMode.Normal;
        buffer.cursor.x = max(1, buffer.cursor.x - 1);
        buffer.cursor.prev_x = buffer.cursor.x;
    }
}


buffer_handle_event_normal :: proc(buffer: ^Buffer, event: tb.Event) {
    switch {
    case event.ch == 'i':
        text_begin_insert(buffer.text, buffer.cursor.y, buffer.cursor.x);
        buffer.mode = BufferMode.Insert;

    case event.ch == 'h':
        buffer_move_cursor(buffer, Direction.Left);
    case event.ch == 'j':
        buffer_move_cursor(buffer, Direction.Down);
    case event.ch == 'k':
        buffer_move_cursor(buffer, Direction.Up);
    case event.ch == 'l':
        buffer_move_cursor(buffer, Direction.Right);
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
        assert(attempt_col > 0);
        assert(attempt_col <= line.display_len ||
               (line.display_len == 0 && attempt_col == 1));

        if len(line.content) == line.display_len {
            return attempt_col;
        }

        prev_col := 1;
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
        cursor.y = max(1, cursor.y - 1);

        line := text.lines[cursor.y - 1];
        line_len := line.display_len;
        max_x := line_len == 0 ? 1 : line_len;
        cursor.x = x_fix(line, min(max_x, cursor.prev_x), text.tab_width);

    case .Down:
        cursor.y = min(buffer.height, len(buffer.text.lines), cursor.y + 1);

        line := text.lines[cursor.y - 1];
        line_len := line.display_len;
        max_x := line_len == 0 ? 1 : line_len;
        cursor.x = x_fix(line, min(max_x, cursor.prev_x), text.tab_width);

    case .Left:
        line := text.lines[cursor.y - 1];
        if len(line.content) == line.display_len {
            cursor.x = max(1, cursor.x - 1);
        } else {
            desired_col := max(1, cursor.x - 1);
            prev_col := 1;
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
        line := text.lines[cursor.y - 1];
        line_len := line.display_len;
        if line_len == 0 {
            cursor.x = 1;
        } else {
            cursor.x = x_fix(line, min(line_len, cursor.x + 1), text.tab_width);
        }
        cursor.prev_x = cursor.x;
    }
}


render_buffer :: proc(buffer: ^Buffer) {
    for line := 1; line <= len(buffer.text.lines) && line <= buffer.height; line += 1 {
        line_len := text_line_display_len(buffer.text, line);

        col := 1;
        for char in string(buffer.text.lines[line - 1].content[:]) {
            switch {
            case char >= 256:
                // utf8 char
                // assumed to only take one displayable char
                fallthrough;
            case char >= DISPLAYABLE_ASCII_MIN && char <= DISPLAYABLE_ASCII_MAX:
                // single cell ascii char
                tb.change_cell(i32(col - 1), i32(line - 1), char,
                               tb.Color.DEFAULT, tb.Color.DEFAULT);
                col += 1;
            case char == '\t':
                for _ in 1..buffer.text.tab_width {
                    tb.change_cell(i32(col - 1), i32(line - 1), rune(' '),
                                   tb.Color.DEFAULT, tb.Color.DEFAULT);
                    col += 1;
                }
            case:
                // multi cell ascii escape code
                display_str := AsciiDisplayTable[char];
                for display_char in display_str {
                    tb.change_cell(i32(col - 1), i32(line - 1), display_char,
                                   tb.Color.DEFAULT, tb.Color.DEFAULT);
                    col += 1;
                }
            }

            if col > line_len || col > buffer.width do break;
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

    tb.set_cursor(cast(i32)buffer.cursor.x - 1, cast(i32)buffer.cursor.y - 1);
    tb.present();
}
