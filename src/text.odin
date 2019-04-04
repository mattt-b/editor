package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:unicode/utf8"

using import "util/stack"


Text :: struct {
    lines: [dynamic]Line,

    past_changes: [dynamic]TextChangeSet,
    current_change: TextChangeSet,

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


TextChangeSet :: struct {
    line: int,
    index: int,

    cursor_line: int,
    cursor_char: int,


    backspaced: TextChange,
    inserted: TextChange,
    deleted: TextChange,
}


TextChange :: struct {
    len: int,
    char_count: int,
    // abc\ndef
    // len = 6
    // newlines = [3]
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
    index := index_in_line(text.lines[line_num], char);
    text.current_change = TextChangeSet{line=line_num, index=index,
                                        cursor_line=line_num, cursor_char=char};
}


text_end_change :: proc(text: ^Text) {
    change := text.current_change;
    has_change := change.inserted.len > 0 || change.backspaced.len > 0 ||
        len(change.inserted.newlines) > 0 || change.deleted.len  > 0 ||
        len(change.backspaced.newlines) > 0 ||
        len(change.deleted.newlines) > 0;
    if !has_change do return;

    append(&text.past_changes, change);
}


text_insert :: proc(text: ^Text, char: rune, line_num, char_num: int) -> bool #require_results {
    line := &text.lines[line_num];

    insert_location := index_in_line(line^, char_num);
    bytes, byte_count := utf8.encode_rune(char);

    ok := line_add(line, insert_location, bytes[:byte_count], 1);
    if !ok do return false;

    text.current_change.inserted.len += byte_count;
    text.current_change.inserted.char_count += 1;
    return true;
}


// TODO: This adds in a line, rename
line_add :: proc(line: ^Line, index: int, bytes: []u8, chars := 0) -> bool #require_results {
    byte_count := len(bytes);
    if index < len(line.content) {
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
        copy(line.content[index + byte_count:], line.content[index:]);
        // Insert char
        copy(line.content[index:], bytes);
    } else if index == len(line.content) || len(line.content) == 0 {
        // appending at the end of a line
        append(&line.content, ..bytes);
    } else {
        unimplemented("Can only append directly after a line");
    }

    if chars == 0 && byte_count != 0 {
        line.char_count += utf8.rune_count(bytes);
    } else {
        line.char_count += chars;
    }
    return true;
}


text_insert_newline :: proc(text: ^Text, line, char: int) -> bool #require_results {
    index := index_in_line(text.lines[line], char);

    ok := text_add_newline(text, line, index);
    if !ok do return false;

    append(&text.current_change.inserted.newlines, text.current_change.inserted.len);
    return true;
}


text_add_newline :: proc(text: ^Text, line_num, index: int) -> bool #require_results {
    current_line := &text.lines[line_num];
    new_line: Line;

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

    return true;
}


text_backspace :: proc(text: ^Text, line_num, char_num: int) {
    if char_num == 0 { // backspacing newline
        if line_num == 0 do unreachable();

        if len(text.current_change.inserted.newlines) != 0 {
            // Backspacing a newline added this edit
            resize(&text.current_change.inserted.newlines,
                  len(text.current_change.inserted.newlines) - 1);
        } else {
            append(&text.current_change.backspaced.newlines,
                   text.current_change.backspaced.len);
            text.current_change.line -= 1;
            text.current_change.index = len(text.lines[text.current_change.line].content);
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
        text.current_change.index -= byte_count;
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
    removed := line_remove(line, deletion_index, byte_count, 1);
    append(&text.deletions, ..removed);

    text.current_change.deleted.char_count += 1;
    text.current_change.deleted.len += byte_count;
}


// TODO: This removes in a line, rename
line_remove :: proc(line: ^Line, index, byte_count: int, char_count := 0,
                    allocator := context.temp_allocator)-> []u8 {
    result := make([]u8, byte_count, allocator);

    copy(result, line.content[index:index+byte_count]);
    if index + byte_count < len(line.content) {
        // Not the last char in the line, shift everything over
        copy(line.content[index:], line.content[index+byte_count:]);
    }

    if char_count == 0 && byte_count != 0 {
        line.char_count -= utf8.rune_count(result);
    } else {
        line.char_count -= char_count;
    }
    (^mem.Raw_Dynamic_Array)(&line.content).len -= byte_count;

    return result;
}


text_merge_lines :: proc(text: ^Text, first, second: int) {
    // TODO: handle failure
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


text_undo :: proc(text: ^Text) -> bool #require_results {
    change := pop(&text.past_changes);

    line_num := change.line;
    index := change.index;
    line: ^Line;

    has_multibyte: bool;
    byte_count: int;
    handle_newline: bool;
    next_newline: int;
    bytes: []u8;
    ok: bool;

    // TODO: Test if it's faster to do these iteratively as is being done here,
    // or moving all of the bytes first and then handling the newlines
    // Make sure to test with multibyte chars
    if change.backspaced.len != 0 || len(change.backspaced.newlines) != 0 {
        has_multibyte = change.backspaced.char_count != change.backspaced.len;
        bytes_remaining := change.backspaced.len;
        newlines_remaining := len(change.backspaced.newlines);

        for bytes_remaining > 0 || newlines_remaining > 0 {
            if newlines_remaining != 0 {
                handle_newline = true;
                next_newline = change.backspaced.newlines[newlines_remaining-1];
                newlines_remaining -= 1;
                byte_count = bytes_remaining - next_newline;
            } else {
                byte_count = bytes_remaining;
                handle_newline = false;
            }

            if byte_count != 0 {
                bytes = pop_rs(&text.backspaces, byte_count);
                line = &text.lines[line_num];
                if !has_multibyte {
                    ok = line_add(line, index, bytes, byte_count);
                } else {
                    ok = line_add(line, index, bytes);
                }
                if !ok do return false;

                index += byte_count;
                bytes_remaining -= byte_count;
            }

            if handle_newline {
                ok = text_add_newline(text, line_num, index);
                if !ok do return false;
                line_num += 1;
                index = 0;
            }
        }
    }

    if change.inserted.len != 0 || len(change.inserted.newlines) != 0 {
        line = &text.lines[line_num];
        bytes_processed := 0;
        total_bytes := change.inserted.len;
        newlines_processed := 0;
        num_newlines := len(change.inserted.newlines);
        has_multibyte = change.inserted.char_count != total_bytes;

        for bytes_processed < total_bytes || newlines_processed < num_newlines {
            if newlines_processed < num_newlines {
                handle_newline = true;
                next_newline = change.inserted.newlines[newlines_processed];
                newlines_processed += 1;
                byte_count = next_newline - bytes_processed;
            } else {
                handle_newline = false;
                byte_count = total_bytes - bytes_processed;
            }

            if byte_count != 0 {
                // TODO: Need to handle these for re-do
                if !has_multibyte {
                    _ = line_remove(line, index, byte_count, byte_count);
                } else {
                    _ = line_remove(line, index, byte_count);
                }
                bytes_processed += byte_count;
            }

            if handle_newline {
                text_merge_lines(text, line_num, line_num+1);
            }
        }
    }

    if change.deleted.len != 0 || len(change.deleted.newlines) != 0 {
        bytes_processed := 0;
        total_bytes := change.deleted.len;
        has_multibyte = change.deleted.char_count != total_bytes;
        newlines_processed := 0;
        num_newlines := len(change.deleted.newlines);
        deletion_start := len(text.deletions) - total_bytes;

        for bytes_processed < total_bytes || newlines_processed < num_newlines {
            line = &text.lines[line_num];

            if newlines_processed < num_newlines {
                handle_newline = true;
                next_newline = change.deleted.newlines[newlines_processed];
                newlines_processed += 1;
                byte_count = next_newline - bytes_processed;
            } else {
                handle_newline = false;
                byte_count = total_bytes - bytes_processed;
            }

            if byte_count != 0 {
                bytes = text.deletions[deletion_start+bytes_processed:
                                      deletion_start+bytes_processed+byte_count];
                if !has_multibyte {
                    ok = line_add(line, index, bytes, byte_count);
                } else {
                    ok = line_add(line, index, bytes);
                }
                if !ok do return false;

                bytes_processed += byte_count;
                index += byte_count;
            }

            if handle_newline {
                ok = text_add_newline(text, line_num, index);
                if !ok do return false;
                line_num += 1;
                index = 0;
            }
        }

        resize(&text.deletions, len(text.deletions) - change.deleted.len);
    }

    return true;
}
