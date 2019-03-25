package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:unicode/utf8"


Text :: struct {
    lines: [dynamic]Line,

    current_change: TextChange,

    line_end_style: LineEndStyle,
    tab_width: int,
}


Line :: struct {
    content: [dynamic]u8,

    // Number of utf8 'rune's
    char_count: int,
}


TextChange :: struct {
    line: int,
    index: int,

    backspaced: int,
    inserted: int,
    deleted: int,
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


text_begin_insert :: proc(text: ^Text, line_num, char: int) {
    line := text.lines[line_num];
    if len(line.content) == line.char_count {
        text.current_change = TextChange{line=line_num, index=char};
    } else {
        total_bytes_read := 0;
        for current_char := 0; current_char < char; {
            _, rune_len := utf8.decode_rune(line.content[total_bytes_read:]);
            total_bytes_read += rune_len;
            current_char += 1;
        }
        text.current_change = TextChange{line=line_num, index=total_bytes_read};
    }
}


text_insert :: proc(text: ^Text, char: rune) -> bool #require_results {
    bytes, count := utf8.encode_rune(char);

    line := &text.lines[text.current_change.line];

    // NOTE: This gets a bit into Odin dynamic array implementation details.
    // Since we aren't appending, we miss out on the normal
    // growth function for this array. Resize would continually give
    // the bare minimum growth causing a realloc and memcpy everytime
    if cap(line.content) < len(line.content) + count {
        ok := reserve(&line.content, 2 * cap(line.content) + 8);
        if !ok do return false;
    }
    ok := resize(&line.content, len(line.content) + count);
    if !ok do return false;

    insert_location := text.current_change.index + text.current_change.inserted;
    // Move existing text over
    copy(line.content[insert_location + count:], line.content[insert_location:]);
    // Insert char
    copy(line.content[insert_location:], bytes[:count]);
    text.current_change.inserted += count;

    line.char_count += 1;
    return true;
}


text_delete :: proc(text: ^Text) {
    line := &text.lines[text.current_change.line];
    deletion_index := text.current_change.index + text.current_change.inserted;

    byte_count: int;
    if len(line.content) == line.char_count {
        byte_count = 1;
    } else {
        // This is the character being deleted. Need to check if it's a multibyte char
        _, byte_count = utf8.decode_rune(line.content[deletion_index:]);
    }

    copy(line.content[deletion_index:], line.content[deletion_index+byte_count:]);
    (^mem.Raw_Dynamic_Array)(&line.content).len -= byte_count;

    line.char_count -= 1;
    text.current_change.deleted += 1;
}
