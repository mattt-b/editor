package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:unicode/utf8"

import "util"


Text :: struct {
    lines: [dynamic]Line,

    past: [dynamic]TextChange,
    current_change: TextChange,
    future: [dynamic]TextChange,

    line_end_style: LineEndStyle,
    tab_width: int,
}


Line :: struct {
    content: [dynamic]u8,

    // Number of displayable characters.
    // For example a utf8 char might take two bytes but only display
    // as one char, or an escape char might take one byte but display as two.
    // Tabs will also affect this unless tab_width == 1
    display_len: int,
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
    file_data, err := util.mmap(fd);
    if err != 0 {
        fmt.println_err("Error reading file");
        unimplemented();
    }
    text.tab_width = 4;

    // Default to LF if this ends up being a one line file
    text.line_end_style = LineEndStyle.LF;
    total_bytes_read := 0;
    line_display_len := 0;

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

        if char == '\t' {
            line_display_len += text.tab_width;
        } else if char < 128 {
            line_display_len += ascii_display_len(char);
        } else {
            line_display_len += 1;
        }
        total_bytes_read += rune_len;
    }

    // Set up rest of lines
    line_start := 0;
    for {
        // Handle the case that the file does not end on a newline
        if total_bytes_read == len(file_data) {
            line_content := make([dynamic]u8, total_bytes_read - line_start);
            mem.copy(&line_content[0], &file_data[line_start], total_bytes_read - line_start);
            append(&text.lines, Line{content=line_content, display_len=line_display_len});
            break;
        }

        char, rune_len := utf8.decode_rune(file_data[total_bytes_read:]);

        if char == rune(text.line_end_style) {
            line_content := make([dynamic]u8, total_bytes_read - line_start);
            if total_bytes_read - line_start > 0 {
                mem.copy(&line_content[0], &file_data[line_start], total_bytes_read - line_start);
            }
            append(&text.lines, Line{content=line_content, display_len=line_display_len});

            line_display_len = 0;

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

        if char == '\t' {
            line_display_len += text.tab_width;
        } else if char < 128 {
            line_display_len += ascii_display_len(char);
        } else {
            line_display_len += 1;
        }
        total_bytes_read += rune_len;
    }

    return true;
}


text_line_display_len :: inline proc(text: ^Text, line_num: int) -> int {
    return text.lines[line_num - 1].display_len;
}


text_begin_insert :: proc(text: ^Text, line_num, col: int) {
    line := text.lines[line_num - 1];
    if len(line.content) == line.display_len {
        text.current_change = TextChange{line=line_num, index=col-1};
    } else {
        total_bytes_read := 0;
        for current_col := 1; current_col < col; {
            char, rune_len := utf8.decode_rune(line.content[total_bytes_read:]);
            total_bytes_read += rune_len;
            if char == '\t' {
                current_col += text.tab_width;
            } else if char < 128 {
                current_col += ascii_display_len(char);
            } else {
                current_col += 1;
            }
        }
        text.current_change = TextChange{line=line_num, index=total_bytes_read};
    }
}


text_insert :: proc(text: ^Text, char: rune) -> bool #require_results {
    bytes, count := utf8.encode_rune(char);

    line := &text.lines[text.current_change.line - 1];

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

    if char == '\t' {
        line.display_len += text.tab_width;
    } else if char < 128 {
        line.display_len += ascii_display_len(char);
    } else {
        line.display_len += 1;
    }
    return true;
}
