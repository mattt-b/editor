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
    buf.cursor.x = 0;
    buf.cursor.y = 0;
    buf.text = new(Text);
    ok := text_init(buf.text, fd);
    if !ok {
        unimplemented();
    }
    return true;
}


buffer_handle_event_insert :: proc(buffer: ^Buffer, event: tb.Event) {
    switch true {
    case event.key == tb.Key.ESC:
        buffer.mode = BufferMode.Normal;
    }
}


buffer_handle_event_normal :: proc(buffer: ^Buffer, event: tb.Event) {
    switch true {
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
    case BufferMode.Normal:
        buffer_handle_event_normal(buffer, event);
    case BufferMode.Insert:
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
        cursor.y = max(0, cursor.y - 1);

        line_len := line_len(text, cursor.y);
        max_x := line_len == 0 ? 0 : line_len - 1;
        cursor.x = min(max_x, cursor.prev_x);

    case Direction.Down:
        cursor.y = min(buffer.height - 1, line_count(buffer.text)-1, cursor.y + 1);

        line_len := line_len(text, cursor.y);
        max_x := line_len == 0 ? 0 : line_len - 1;
        cursor.x = min(max_x, cursor.prev_x);

    case Direction.Left:
        cursor.x = max(0, cursor.x - 1);
        cursor.prev_x = cursor.x;

    case Direction.Right:
        line_len := line_len(text, cursor.y);
        if line_len == 0 {
            cursor.x = 0;
        } else {
            cursor.x = min(line_len - 1, cursor.x + 1);
        }
        cursor.prev_x = cursor.x;
    }
}

render_buffer :: proc(buffer: ^Buffer) {
    y := 0;
    x := 0;
    piece := buffer.text.pieces;
    for piece != nil {
        content := piece.content;
        for i := 0; i < len(content); i += 1{
            if buffer.height == y do break;
            if (buffer.width == x || content[i] == '\n') {
                // advance to next line
                y += 1;
                x = 0;
                continue;
            };

            tb.change_cell(i32(x), i32(y), cast(u32)content[i], tb.Color.DEFAULT, tb.Color.DEFAULT);
            x += 1;
        }

        piece = piece.next;
    }

    tb.set_cursor(cast(i32)buffer.cursor.x, cast(i32)buffer.cursor.y);
    tb.present();
}
