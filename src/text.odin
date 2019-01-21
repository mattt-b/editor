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


LineStart :: struct {
  piece: ^Piece,
  index: int,
}


TextIterator :: struct {
    text: ^Text,
    // Piece that is currently being iterated over
    piece: ^Piece,
    // Index in piece currently being iterated
    index: int,
}


Text :: struct {
    original: []u8,
    pieces: ^Piece,
    lines: [dynamic]LineStart,
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

    text_set_lines(text);

    return true;
}


text_set_lines :: proc(text: ^Text) {
    if len(text.lines) != 0 do clear_dynamic_array(&text.lines);

    piece := text.pieces;
    new_line := LineStart{piece=piece, index=0};
    append(&text.lines, new_line);

    for {
        for char, index in piece.content {
            if char != '\n' do continue;

            if len(piece.content) == index + 1 {
                // This '\n' is on a piece boundary
                // If it's the last piece, we're done
                if piece.next == nil do return;
                // otherwise, ensure we move on to the next piece for the LineStart
                new_line = LineStart{piece=piece.next, index=0};
            } else {
                // Add + 1 to index the first char after '\n'
                new_line = LineStart{piece=piece, index=index + 1};
            }
            append(&text.lines, new_line);
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

    // translate cursor space to data space
    line := text.lines[line_num - 1];

    if len(text.lines) == line_num {
        unreachable();
    }

    next_line := text.lines[line_num - 1 + 1];
    if next_line.piece == line.piece {
        // Simplest case. This piece holds the full line.
        // Early out here to simplify logic when looping through pieces below
        // -1 to account for newline that is skipped
        return next_line.index - line.index - 1;
    }

    length := len(line.piece.content) - line.index;
    // This is holding the piece whose length we are checking
    // and it will change through the loop
    assert(line.piece.next != nil);
    piece := line.piece.next;
    for {
        if piece == next_line.piece {
            length += next_line.index;
            // - 1 to account for newline that is skipped
            return length - 1;
        }

        unreachable();
        // This piece does not contain the next LineStart
        length += len(piece.content);
        assert(piece.next != nil);
        piece = piece.next;
    }
    unreachable();
    return 0;
}


line_count :: proc(text: ^Text) -> int {
    return 1;
}
