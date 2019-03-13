package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:unicode/utf8"

import "util"


Text :: struct {
    // Not actually dynamic. Just matching type
    // signatures with 'change' for now
    original: [dynamic]u8,
    updates: [dynamic]u8,

    changes: TextChanges,

    pieces: ^Piece,
    lines: [dynamic]Line,

    line_end_style: LineEndStyle,
    tab_width: int,
}


Piece :: struct {
    content: ^[dynamic]u8,
    start: int,
    len: int,
    prev: ^Piece,
    next: ^Piece,
}


TextChanges :: struct {
    any: bool,

    prev: ^Piece,
    insert: ^Piece,
    next: ^Piece,

    replacing_prev: ^Piece,
    replacing_next: ^Piece,
}


Line :: struct {
    piece: ^Piece,
    // At what byte index in the piece this Line starts at
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


text_init :: proc(text: ^Text, fd: os.Handle) -> bool #require_results {
    file_data, err := util.mmap(fd);
    if err != 0 {
        fmt.println_err("Error reading file");
        exit(1);
        unimplemented();
    }
    text.tab_width = 4;

    // change the file_data slice to a [dynamic]u8 to match signatures
    // with the 'text.changes' [array]
    text.original = transmute([dynamic]u8)mem.Raw_Dynamic_Array{
        data=(^mem.Raw_Slice)(&file_data).data,
        len=len(file_data),
        cap=len(file_data),
        // ensure this can't be resized on accident
        allocator=mem.nil_allocator(),
    };

    initial_piece := new(Piece);
    initial_piece.content = &text.original;
    initial_piece.len= len(file_data);
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
            if len(file_data) == total_bytes_read + 1 {
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

            if piece_bytes_read == piece.len {
                if piece.next == nil do return;
                piece = piece.next;
                piece_bytes_read = 0;
            }
            continue;
        }

        // If we get here we're on a newline char start: \n or \r
        // save this line information and set up the next one
        line.file_len = file_len;
        line.display_len = display_len;
        append(&text.lines, line);

        file_len = 0;
        display_len = 0;

        at_piece_end := piece_bytes_read == piece.len;
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
            at_piece_end = piece_bytes_read == piece.len;
        }

        if at_piece_end {
            line = Line{piece=piece.next, index=0};
            break single_piece;
        } else {
            line = Line{piece=piece, index=piece_bytes_read};
        }
    }
}


text_iterator_init :: proc(iterator: ^TextIterator, text: ^Text, line_num := 1) {
    iterator.text = text;
    iterator.piece = text.lines[line_num - 1].piece;
    iterator.index = text.lines[line_num - 1].index;
}


text_iterate_next :: proc(iterator: ^TextIterator) -> (rune, bool) {
    if iterator.index >= iterator.piece.len {
        assert(iterator.piece.next != nil);
        iterator.piece = iterator.piece.next;
        assert(iterator.piece.len > 0);
        iterator.index = 0;
    }

    char, rune_len := utf8.decode_rune(iterator.piece.content[iterator.index:]);
    iterator.index += rune_len;

    return char, true;
}


text_line_display_len :: inline proc(text: ^Text, line_num: int) -> int {
    return text.lines[line_num - 1].display_len;
}


text_begin_insert :: proc(text: ^Text, line_num, col: int) -> bool #require_results {
    text.changes.any = false;

    // Create the pieces if they don't exist already
    if text.changes.insert == nil {
        // TODO: Probably should use a custom allocator to put them
        // all in the same spot
        insert_piece := new(Piece);
        if insert_piece == nil do return false;

        insert_piece.content = &text.updates;
        text.changes.insert = insert_piece;
    }

    // Here we either have a new piece or we are re-purposing an unused piece
    // (from going into insert mode but not making any changes).
    text.changes.insert.start = len(text.updates);

    // TODO: special case not needing the iterator?

    // figure out the piece/byte offset to split prev at
    text_iterator: TextIterator;
    text_iterator_init(&text_iterator, text, line_num);
    more := true;
    for i := 1; i < col; i += 1 {
        assert(more);
        _, more = text_iterate_next(&text_iterator);
    }

    text.changes.replacing_prev = text_iterator.piece;
    if line_num != 1 || col != 1 {
        assert(text_iterator.piece.prev != nil || text_iterator.index != 0);
        prev_piece := new(Piece);
        if prev_piece == nil do return false;

        prev_piece^ = text_iterator.piece^;
        prev_piece.len = text_iterator.index;
        prev_piece.next = text.changes.insert;

        text.changes.prev = prev_piece;
        text.changes.insert.prev = prev_piece;
    } else {
        // Do nothing. Prev pieces will remain nil and checked for later
    }

    // this will handle the event that we're on a piece boundary
    // so we can find the next piece
    if more do _, more = text_iterate_next(&text_iterator);

    if more {
        next_piece := new(Piece);
        if next_piece == nil do return false;
        next_piece^ = text_iterator.piece^;

        next_piece.start = text_iterator.index;
        next_piece.len -= text_iterator.index;
        next_piece.prev = text.changes.insert;

        text.changes.insert.next = next_piece;
        text.changes.next = next_piece;
    } else {
        // Do nothing. Next pieces will remain nil and checked for later
    }

    return true;
}


text_insert :: proc(text: ^Text, char: rune) {
    bytes, count := utf8.encode_rune(char);
    append(&text.updates, ..bytes[:count]);

    text.changes.insert.len += count;

    if !text.changes.any {
        // First additions. Insert the new pieces into the piece table
        text.changes.any = true;

        if text.changes.replacing_prev.prev != nil {
            text.changes.replacing_prev.prev.next = text.changes.prev;
        } else {
            // In this block we're replacing the first piece
            if text.changes.prev != nil {
                // Normal case, anything other than line 1 col 1
                text.pieces = text.changes.prev;
            } else {
                // Inserting into line 1 col 1
                text.pieces = text.changes.insert;
            }
        }

    }

    // TODO: Think this out better.
    text_set_lines(text);
}
