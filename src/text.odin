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


Text :: struct {
    original: []u8,
    // The first piece is a sentinel piece that will never be removed
    pieces: ^Piece,
}


text_init :: proc(text: ^Text, fd: os.Handle) -> bool {
    file_data, err := util.mmap(fd);
    if err != 0 {
        fmt.println_err("Error reading file");
        exit(1);
        unimplemented();
    }

    text.original = file_data;
    text.pieces = new(Piece);

    initial_piece := new(Piece);
    initial_piece.source = TextSource.Original;
    initial_piece.content = file_data[0:len(file_data)];
    text.pieces.next = initial_piece;
    return true;
}


text_insert_char_at_line_col :: proc(text: ^Text, char: u8, line: int, col: int) {
}


line_len :: proc(text: ^Text, line_num: int) -> int {
    return 1;
}


line_count :: proc(text: ^Text) -> int {
    return 1;
}
