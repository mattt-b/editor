package main


DISPLAYABLE_ASCII_MIN :: 32;
DISPLAYABLE_ASCII_MAX :: 126;

ascii_display_len :: inline proc(char: rune) -> int {
    assert(char < 128);
    assert(char != 9);
    assert(char != 10);
    return len(AsciiDisplayTable[char]);
}


AsciiDisplayTable := [128]string{
    "^@", // NULL
    "^A", // start of heading
    "^B", // start of text
    "^C", // end of text
    "^D", // end of transmission
    "^E", // enquiry
    "^F", // acknowledge
    "^G", // bell
    "^H", // backspace

    // These should never be accessed?
    "", // tab
    "", // LF

    "^K", // vertical tab
    "^L", // form feed
    "^M", // CR
    "^N", // shift in
    "^O", // shift out
    "^P", // data link escape
    "^Q", // device control 1
    "^R", // device control 2
    "^S", // device control 3
    "^T", // device control 4
    "^U", // negative acknowledge
    "^V", // synchronous idle
    "^W", // end of transmission block
    "^X", // cancel
    "^Y", // end of medium
    "^Z", // substitute
    "^[", // escape
    "^\\", // file separator
    "^]", // group separator
    "^^", // record separator
    "^_", // unit separator

    " ",
    "!",
    "\"",
    "#",
    "$",
    "%",
    "&",
    "'",
    "(",
    ")",
    "*",
    "+",
    ",",
    "-",
    ".",
    "/",
    "0",
    "1",
    "2",
    "3",
    "4",
    "5",
    "6",
    "7",
    "8",
    "9",
    ":",
    ";",
    "<",
    "=",
    ">",
    "?",
    "@",
    "A",
    "B",
    "C",
    "D",
    "E",
    "F",
    "G",
    "H",
    "I",
    "J",
    "K",
    "L",
    "M",
    "N",
    "O",
    "P",
    "Q",
    "R",
    "S",
    "T",
    "U",
    "V",
    "W",
    "X",
    "Y",
    "Z",
    "[",
    "\\",
    "]",
    "^",
    "_",
    "`",
    "a",
    "b",
    "c",
    "d",
    "e",
    "f",
    "g",
    "h",
    "i",
    "j",
    "k",
    "l",
    "m",
    "n",
    "o",
    "p",
    "q",
    "r",
    "s",
    "t",
    "u",
    "v",
    "w",
    "x",
    "y",
    "z",
    "{",
    "|",
    "}",
    "~",

    "^?", // delete
};
