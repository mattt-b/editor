package main

import "core:os"

import "util"

TextSource :: enum u8 {
    Original,
    Append,
}

Piece :: struct {
    source: TextSource,
    content: []u8,
}


Linebreak :: struct {
}


Text :: struct {
    original: []u8,
    pieces: [dynamic]Piece,
    linebreaks: [dynamic]Linebreak,
    lines: [dynamic][]u8,
}


text_init :: proc(text: ^Text, fd: os.Handle) {
    file_data := util.mmap(fd);
    text.original = file_data;
    initial_piece := Piece{
        source=TextSource.Original,
        content=file_data[0:len(file_data)],
    };
    append(&text.pieces, initial_piece);
}


line_len :: proc(text: ^Text, line_num: int) {
}
