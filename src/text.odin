package main

import "core:fmt"
import "core:os"

import "util"


TextSource :: enum u8 {
    Original,
    Append,
}


Piece :: struct {
    source: TextSource,
    content: []u8,
    prev: ^Piece,
    next: ^Piece,
}


Line :: struct {
    piece: ^Piece,
    index: int,
    length: int,
}

LineEndStyle :: enum u8 {
    LF = '\n',
    CRLF = '\r',
}


TextIterator :: struct {
    text: ^Text,
    // Piece that is currently being iterated over
    piece: ^Piece,
    // Index in piece currently being iterated
    index: int,
}


Text :: struct {
    line_end_style: LineEndStyle,
    original: []u8,
    pieces: ^Piece,
    lines: [dynamic]Line,
}


text_init :: proc(text: ^Text, fd: os.Handle) -> bool {
    file_data, err := util.mmap(fd);
    if err != 0 {
        fmt.println_err("Error reading file");
        exit(1);
        unimplemented();
    }

    text.original = file_data;

    initial_piece := new(Piece);
    initial_piece.source = TextSource.Original;
    initial_piece.content = file_data[0:len(file_data)];
    text.pieces = initial_piece;

    // Default to LF
    text.line_end_style = LineEndStyle.LF;
    // Set it to something else if detected
    for char, i in file_data {
        if char == '\n' {
            text.line_end_style = LineEndStyle.LF;
            break;
        }
        if char == '\r' {
            if len(file_data) >= i + 1 + 1 {
                unimplemented("Not handling bare CR");
            }
            if file_data[i + 1] == '\n' {
                text.line_end_style = LineEndStyle.CRLF;
                break;
            } else {
                unimplemented("Not handling bare CR");
            }
        }
    }

    text_set_lines(text);

    return true;
}


text_set_lines :: proc(text: ^Text) {
    if len(text.lines) != 0 do clear_dynamic_array(&text.lines);

    piece := text.pieces;
    new_line := Line{piece=piece, index=0};
    length := 0;
    for {
        for char, i in piece.content {
            if char != u8(text.line_end_style) {
                length += 1;
                continue;
            }

            new_line.length = length;
            append(&text.lines, new_line);
            length = 0;

            if text.line_end_style == LineEndStyle.CRLF do unimplemented("FIXME: Handle CRLF");
            if len(piece.content) == i + 1 {
                // This line ending is on a piece boundary
                // If it's the last piece, we're done
                if piece.next == nil do return;
                // otherwise, ensure we move on to the next piece for the LineStart
                new_line = Line{piece=piece.next, index=0};
            } else {
                // Add + 1 to index the first char after '\n'
                new_line = Line{piece=piece, index=i + 1};
            }
        }
        if piece.next == nil do return;
        piece = piece.next;
    }
}


text_iterator_init :: proc(iterator: ^TextIterator, text: ^Text) {
    iterator.text = text;
    iterator.piece = text.pieces;
    iterator.index = 0;
}


text_iterate_next :: proc(iterator: ^TextIterator) -> (u8, bool) {
    if len(iterator.piece.content) <= iterator.index {
        if iterator.piece.next == nil do return 0, false;

        iterator.piece = iterator.piece.next;
        assert(len(iterator.piece.content) > 0);
        iterator.index = 0;
    }

    char := iterator.piece.content[iterator.index];
    iterator.index += 1;

    return char, true;
}


line_len :: proc(text: ^Text, line_num: int) -> int {
    assert(line_num > 0);
    assert(line_num <= len(text.lines));

    return text.lines[line_num - 1].length;
}


line_count :: proc(text: ^Text) -> int {
    return 1;
}
