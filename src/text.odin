package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:unicode/utf8"

using import "util/stack"


Text :: struct {
    lines: [dynamic]Line,

    current_change: TextChange,

    line_end_style: LineEndStyle,
    tab_width: int,

    backspaces: ReverseStack(u8),
    deletions: [dynamic]u8,

    fd: os.Handle,
}


Line :: struct {
    content: [dynamic]u8,

    // Number of utf8 'rune's
    char_count: int,
}


TextChange :: struct {
    backspaced: BackspaceChange,
    inserted: InsertionChange,
    deleted: DeletionChange,
}


BackspaceChange :: struct {
    index: int,
    len: int,
    char_count: int,
    newlines: [dynamic]int,
}

InsertionChange :: struct {
    line: int,
    index: int,
    len: int,
    char_count: int,
    newlines: [dynamic]int,
}

DeletionChange :: struct {
    index: int,
    len: int,
    char_count: int,
    newlines: [dynamic]int,
}


LineEndStyle :: enum u8 {
    LF = '\n',
    CRLF = '\r',
}


text_init :: proc(text: ^Text, fd: os.Handle) -> bool #require_results {
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

    text.fd = fd;
    text.tab_width = 4;

    // Default to LF if this ends up being a one line file
    text.line_end_style = LineEndStyle.LF;
    total_bytes_read := 0;
    char_count := 0;

    // Figure out line end style and set up first line
    for total_bytes_read < len(file_data) {
        char, rune_len := utf8.decode_rune(file_data[total_bytes_read:]);

        if char == '\n' {
            text.line_end_style = LineEndStyle.LF;
            break;
        }
        if char == '\r' {
            if len(file_data) == total_bytes_read + 1 {
                unimplemented("Not handling bare CR");
            }

            next_char, _ := utf8.decode_rune(file_data[total_bytes_read+1:]);
            if next_char == '\n' {
                text.line_end_style = LineEndStyle.CRLF;
                break;
            } else {
                unimplemented("Not handling bare CR");
            }
        }

        char_count += 1;
        total_bytes_read += rune_len;
    }

    // Set up rest of lines
    line_start := 0;
    for {
        // Handle the case that the file does not end on a newline
        if total_bytes_read == len(file_data) {
            line_content := make([dynamic]u8, total_bytes_read - line_start);
            mem.copy(&line_content[0], &file_data[line_start], total_bytes_read - line_start);
            append(&text.lines, Line{content=line_content, char_count=char_count});
            break;
        }

        char, rune_len := utf8.decode_rune(file_data[total_bytes_read:]);

        if char == rune(text.line_end_style) {
            line_content := make([dynamic]u8, total_bytes_read - line_start);
            if total_bytes_read - line_start > 0 {
                mem.copy(&line_content[0], &file_data[line_start], total_bytes_read - line_start);
            }
            append(&text.lines, Line{content=line_content, char_count=char_count});

            char_count = 0;

            total_bytes_read += rune_len;
            line_start = total_bytes_read;

            #complete switch text.line_end_style {
                case .LF:
                case .CRLF:
                char, rune_len = utf8.decode_rune(file_data[total_bytes_read:]);
                assert(char == '\n', "Bare \r not currently supported");
                total_bytes_read += rune_len;
            }
            if total_bytes_read == len(file_data) do break;
            continue;
        }

        char_count += 1;
        total_bytes_read += rune_len;
    }

    return true;
}


index_in_line :: proc(line: Line, char: int) -> int {
    assert(char <= line.char_count);
    if len(line.content) == line.char_count do return char;

    total_bytes_read := 0;
    for i := 0; i < char; i += 1 {
        _, char_bytes := utf8.decode_rune(line.content[total_bytes_read:]);
        total_bytes_read += char_bytes;
    }
    return total_bytes_read;
}

text_begin_change :: proc(text: ^Text, line_num, char: int) {
    line := text.lines[line_num];
    insertion_change := InsertionChange{line=line_num};

    if len(line.content) == line.char_count {
        insertion_change.index = char;
    } else {
        total_bytes_read := 0;
        for current_char := 0; current_char < char; {
            _, rune_len := utf8.decode_rune(line.content[total_bytes_read:]);
            total_bytes_read += rune_len;
            current_char += 1;
        }
        insertion_change.index = total_bytes_read;
    }

    text.current_change.backspaced = BackspaceChange{index=text.backspaces.len};
    text.current_change.inserted = insertion_change;
    text.current_change.deleted = DeletionChange{index=len(text.deletions)};
}


text_insert :: proc(text: ^Text, char: rune,
                    line_num, char_num: int) -> bool #require_results {
    line := &text.lines[line_num];

    insert_location := index_in_line(line^, char_num);
    bytes, byte_count := utf8.encode_rune(char);


    if insert_location < len(line.content) {
        // NOTE: This gets a bit into Odin dynamic array implementation details.
        // Since we aren't appending, we miss out on the normal
        // growth function for this array. Resize would continually give
        // the bare minimum growth causing a realloc and memcpy everytime
        if cap(line.content) < len(line.content) + byte_count {
            ok := reserve(&line.content, 2 * cap(line.content) + 8);
            if !ok do return false;
        }
        ok := resize(&line.content, len(line.content) + byte_count);
        if !ok do return false;

        // Inserting
        // Move existing text over
        copy(line.content[insert_location + byte_count:], line.content[insert_location:]);
        // Insert char
        copy(line.content[insert_location:], bytes[:byte_count]);
    } else if insert_location == len(line.content) || len(line.content) == 0 {
        // appending at the end of a line
        append(&line.content, ..bytes[:byte_count]);
    } else {
        unimplemented("Can only append directly after a line");
    }

    text.current_change.inserted.len += byte_count;
    text.current_change.inserted.char_count += 1;
    line.char_count += 1;
    return true;
}


text_insert_newline :: proc(text: ^Text, line_num, char_num: int) -> bool #require_results {
    current_line := &text.lines[line_num];
    new_line: Line;
    index := index_in_line(current_line^, char_num);

    assert(len(current_line.content) >= index);
    if len(current_line.content) > index {
        // Inserting the newline in the middle of an existing line.
        // Move content to 'new' line and adjust counts for both
        ok := resize(&new_line.content, len(current_line.content) - index);
        if !ok do return false;
        copy(new_line.content[0:], current_line.content[index:]);

        moved := current_line.char_count - index;
        if len(current_line.content) == current_line.char_count {
            current_line.char_count = current_line.char_count - moved;
            new_line.char_count = moved;
        } else {
            new_line.char_count = utf8.rune_count(new_line.content[:]);
            current_line.char_count = current_line.char_count - new_line.char_count;
        }
        _ = resize(&current_line.content, len(current_line.content) - moved);
    }

    if len(text.lines) - 1 > line_num {
        // Not on the last line
        ok := resize(&text.lines, len(text.lines) + 1);
        if !ok do return false;
        // Move all existing lines down
        copy(text.lines[line_num+2:], text.lines[line_num+1:]);
        text.lines[line_num + 1] = new_line;
    } else {
        // on the last line, just need to append
        append(&text.lines, new_line);
    }
    append(&text.current_change.inserted.newlines, text.current_change.inserted.len);

    return true;
}


text_backspace :: proc(text: ^Text, line_num, char_num: int) {
    if char_num == 0 { // backspacing newline
        if line_num == 0 do return;

        if len(text.current_change.inserted.newlines) != 0 {
            // Backspacing a newline added this edit
            resize(&text.current_change.inserted.newlines,
                  len(text.current_change.inserted.newlines) - 1);
        } else {
            append(&text.current_change.backspaced.newlines, 0);
        }
        text_merge_lines(text, line_num - 1, line_num);
        return;
    }

    line := &text.lines[line_num];
    backspace_char_index, byte_count: int;

    if len(line.content) == line.char_count {
        backspace_char_index = char_num - 1;
        byte_count = 1;
    } else {
        backspace_char_index = index_in_line(line^, char_num - 1);
        _, byte_count = utf8.decode_rune(line.content[backspace_char_index:]);
    }

    if text.current_change.inserted.len > 0 {
        text.current_change.inserted.len -= byte_count;
        text.current_change.inserted.char_count -= 1;
    } else {
        text.current_change.backspaced.len += byte_count;
        text.current_change.backspaced.char_count += 1;
        push_rs(&text.backspaces,
                ..line.content[backspace_char_index:backspace_char_index+byte_count]);
    }

    if len(line.content) > backspace_char_index + byte_count {
        copy(line.content[backspace_char_index:],
             line.content[backspace_char_index + byte_count:]);
    }
    resize(&line.content, len(line.content) - byte_count);
    line.char_count -= 1;
}


text_delete :: proc(text: ^Text, line_num, char_num: int) {
    line := &text.lines[line_num];
    deletion_index := index_in_line(line^, char_num);

    if deletion_index == len(line.content) || len(line.content) == 0 {
        if line_num == len(text.lines) - 1 do return;

        append(&text.current_change.deleted.newlines, text.current_change.deleted.len);
        text_merge_lines(text, line_num, line_num + 1);

        return;
    }

    byte_count: int;
    if len(line.content) == line.char_count {
        byte_count = 1;
    } else {
        // This is the character being deleted. Need to check if it's a multibyte char
        _, byte_count = utf8.decode_rune(line.content[deletion_index:]);
    }

    append(&text.deletions, ..line.content[deletion_index:deletion_index+byte_count]);

    if deletion_index + byte_count < len(line.content) {
        // Not the last char in the line, shift everything over
        copy(line.content[deletion_index:], line.content[deletion_index+byte_count:]);
    }
    (^mem.Raw_Dynamic_Array)(&line.content).len -= byte_count;

    line.char_count -= 1;
    text.current_change.deleted.char_count += 1;
    text.current_change.deleted.len += byte_count;
}


text_merge_lines :: proc(text: ^Text, first, second: int) {
    assert(first < len(text.lines) && second < len(text.lines));
    first_line  := &text.lines[first];
    second_line := text.lines[second];

    // merge lines
    first_line.char_count += second_line.char_count;
    append(&first_line.content, ..second_line.content[:]);

    if second < len(text.lines) - 1 {
        copy(text.lines[second:], text.lines[second+1:]);
    }
    resize(&text.lines, len(text.lines) - 1);
}
