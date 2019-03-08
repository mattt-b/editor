package main

import "core:os"

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

buffer_init :: proc(buf: ^Buffer, fd: os.Handle) -> bool {
    buf.mode = BufferMode.Normal;
    buf.cursor.x = 1;
    buf.cursor.y = 1;
    buf.cursor.prev_x = 1;
    buf.text = new(Text);
    ok := text_init(buf.text, fd);
    if !ok {
        unimplemented();
    }
    return true;
}


buffer_handle_event_insert :: proc(buffer: ^Buffer, event: tb.Event) {
    switch {
    case event.key == tb.Key.ESC:
        buffer.mode = BufferMode.Normal;
    }
}


buffer_handle_event_normal :: proc(buffer: ^Buffer, event: tb.Event) {
    switch {
    case event.ch == 'i':
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
    using Direction;

    switch direction {
    case Direction.Up:
        cursor.y = max(1, cursor.y - 1);

        line_len := text_line_display_len(text, cursor.y);
        max_x := line_len == 0 ? 1 : line_len;
        cursor.x = min(max_x, cursor.prev_x);

    case Direction.Down:
        cursor.y = min(buffer.height, len(buffer.text.lines), cursor.y + 1);

        line_len := text_line_display_len(text, cursor.y);
        max_x := line_len == 0 ? 1 : line_len;
        cursor.x = min(max_x, cursor.prev_x);

    case Direction.Left:
        cursor.x = max(1, cursor.x - 1);
        cursor.prev_x = cursor.x;

    case Direction.Right:
        line_len := text_line_display_len(text, cursor.y);
        if line_len == 0 {
            cursor.x = 1;
        } else {
            cursor.x = min(line_len, cursor.x + 1);
        }
        cursor.prev_x = cursor.x;
    }
}


render_buffer :: proc(buffer: ^Buffer) {
    iterator := TextIterator{};
    for line := 1; line <= len(buffer.text.lines) && line <= buffer.height; line += 1 {
        text_iterator_init(&iterator, buffer.text, line);
        line_len := text_line_display_len(buffer.text, line);

        for col := 1; col <= line_len && col <= buffer.width; {
            char, more := text_iterate_next(&iterator);

            switch {
            case char >= 256:
                // utf8 char
                fallthrough;
            case char >= DISPLAYABLE_ASCII_MIN && char <= DISPLAYABLE_ASCII_MAX:
                // single cell ascii char
                tb.change_cell(i32(col - 1), i32(line - 1), u32(char),
                               tb.Color.DEFAULT, tb.Color.DEFAULT);
                col += 1;
            case char == '\t':
                for _ in 1..buffer.text.tab_width {
                    tb.change_cell(i32(col - 1), i32(line - 1), u32(' '),
                                   tb.Color.DEFAULT, tb.Color.DEFAULT);
                    col += 1;
                }
                case:
                // multi cell ascii escape code
                display_str := AsciiDisplayTable[char];
                for display_char in display_str {
                    tb.change_cell(i32(col - 1), i32(line - 1), u32(display_char),
                                   tb.Color.DEFAULT, tb.Color.DEFAULT);
                    col += 1;
                }
            }

            if !more do break;
        }
    }

    tb.set_cursor(cast(i32)buffer.cursor.x - 1, cast(i32)buffer.cursor.y - 1);
    tb.present();
}
