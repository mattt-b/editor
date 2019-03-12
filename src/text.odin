package main

import "core:fmt"
import "core:os"
import "core:unicode/utf8"

import "util"


Text :: struct {
    original: []u8,
    pieces: ^Piece,
    lines: [dynamic]Line,

    line_end_style: LineEndStyle,
    tab_width: int,
}


Piece :: struct {
    source: TextSource,
    content: []u8,
    prev: ^Piece,
    next: ^Piece,
}


TextSource :: enum u8 {
    Original,
    Append,
}


Line :: struct {
    piece: ^Piece,
    // At what index in the piece this Line starts at
    index: int,
    // How many bytes this line would take
    // in a file. (Newline chars are ignored)
    file_len: int,
    // How much space would be needed to
    // render the entire line
    display_len: int,
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


text_init :: proc(text: ^Text, fd: os.Handle) -> bool {
    file_data, err := util.mmap(fd);
    if err != 0 {
        fmt.println_err("Error reading file");
        exit(1);
        unimplemented();
    }
    text.tab_width = 4;

    text.original = file_data;

    initial_piece := new(Piece);
    initial_piece.source = TextSource.Original;
    initial_piece.content = file_data[0:len(file_data)];
    text.pieces = initial_piece;

    // Default to LF
    text.line_end_style = LineEndStyle.LF;
    // Set it to something else if detected
    total_bytes_read := 0;
    for {
        char, rune_len := utf8.decode_rune(file_data[total_bytes_read:]);
        total_bytes_read += rune_len;
        if char == '\n' {
            text.line_end_style = LineEndStyle.LF;
            break;
        }
        if char == '\r' {
            if len(file_data) >= total_bytes_read + 1 {
                unimplemented("Not handling bare CR");
            }

            next_char, _ := utf8.decode_rune(file_data[total_bytes_read:]);
            if next_char == '\n' {
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
    line := Line{piece=piece, index=0};
    // How many bytes into piece.content we've currently read
    // Reset to 0 on new piece
    piece_bytes_read := 0;
    // Count of bytes for line (ignores newline)
    file_len := 0;
    // Count of runes for line (ignores newline)
    display_len := 0;

    all_pieces: for {
        single_piece: for {
            char, rune_len := utf8.decode_rune(piece.content[piece_bytes_read:]);
            piece_bytes_read += rune_len;

            // not a newline char
            if char != rune(text.line_end_style) {
                // TODO: Any char that needs to be represented
                // as an escape char or multichar code needs to be
                // set here
                if char == '\t' {
                    display_len += text.tab_width;
                } else if char < 128 {
                    // ascii character
                    display_len += ascii_display_len(char);
                } else {
                    // UTF8 rune that's not ascii
                    // treating them all as single displayable runes
                    // (no grapheme clusters)
                    display_len += 1;
                }
                file_len += rune_len;

                if piece_bytes_read == len(piece.content) do break single_piece;
                continue;
            }

            // If we get here we're on a newline char start: \n or \r
            // save this line information and set up the next one
            line.file_len = file_len;
            line.display_len = display_len;
            append(&text.lines, line);

            file_len = 0;
            display_len = 0;

            at_piece_end := piece_bytes_read == len(piece.content);
            if text.line_end_style == LineEndStyle.CRLF {
                // TODO: Should be able to remove all of these if I'm sure
                // that it's not possible to insert \r, and I've made sure
                // that I've checked or fixed bare \r in the initial text
                // setup (where line_end_style is set). Alternatively need
                // to adjust all of this code if bare \r is allowed.
                assert(!at_piece_end, "Shouldn't be able to split \r\n ?");
                char, rune_len = utf8.decode_rune(piece.content[piece_bytes_read:]);
                assert(char == '\n', "Shouldn't be able to split \r\n ?");
                assert(rune_len == 1);

                piece_bytes_read += 1;
                at_piece_end = piece_bytes_read == len(piece.content);
            }

            if at_piece_end {
                line = Line{piece=piece.next, index=0};
                break single_piece;
            } else {
                line = Line{piece=piece, index=piece_bytes_read};
            }
        }

        if piece.next == nil do return;
        piece = piece.next;
        piece_bytes_read = 0;
    }
}


text_iterator_init :: proc(iterator: ^TextIterator, text: ^Text, line_num := 1) {
    assert(line_num > 0);
    assert(line_num <= len(text.lines));

    iterator.text = text;
    iterator.piece = text.lines[line_num - 1].piece;
    iterator.index = text.lines[line_num - 1].index;
}


text_iterate_next :: proc(iterator: ^TextIterator) -> (rune, bool) {
    if len(iterator.piece.content) <= iterator.index {
        if iterator.piece.next == nil {
            unreachable("Does this ever even get hit?");
            return 0, false;
        }

        iterator.piece = iterator.piece.next;
        assert(len(iterator.piece.content) > 0);
        iterator.index = 0;
    }

    char, rune_len := utf8.decode_rune(iterator.piece.content[iterator.index:]);
    iterator.index += rune_len;

    return char, true;
}


text_line_display_len :: inline proc(text: ^Text, line_num: int) -> int {
    assert(line_num > 0);
    assert(line_num <= len(text.lines));

    return text.lines[line_num - 1].display_len;
}
