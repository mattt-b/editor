package main


DISPLAYABLE_ASCII_MIN :: 32;
DISPLAYABLE_ASCII_MAX :: 126;

ascii_display_len :: inline proc(char: rune) -> int {
    assert(char < 256);
    assert(char != 9);
    assert(char != 10);
    return len(AsciiDisplayTable[char]);
}


AsciiDisplayTable := [256]string{
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

    // 128-255 'extended' ascii table
    "<80>",
    "<81>",
    "<82>",
    "<83>",
    "<84>",
    "<85>",
    "<86>",
    "<87>",
    "<88>",
    "<89>",
    "<8A>",
    "<8B>",
    "<8C>",
    "<8D>",
    "<8E>",
    "<8F>",
    "<90>",
    "<91>",
    "<92>",
    "<93>",
    "<94>",
    "<95>",
    "<96>",
    "<97>",
    "<98>",
    "<99>",
    "<9A>",
    "<9B>",
    "<9C>",
    "<9D>",
    "<9E>",
    "<9F>",
    "<A0>",
    "<A1>",
    "<A2>",
    "<A3>",
    "<A4>",
    "<A5>",
    "<A6>",
    "<A7>",
    "<A8>",
    "<A9>",
    "<AA>",
    "<AB>",
    "<AC>",
    "<AD>",
    "<AE>",
    "<AF>",
    "<B0>",
    "<B1>",
    "<B2>",
    "<B3>",
    "<B4>",
    "<B5>",
    "<B6>",
    "<B7>",
    "<B8>",
    "<B9>",
    "<BA>",
    "<BB>",
    "<BC>",
    "<BD>",
    "<BE>",
    "<BF>",
    "<C0>",
    "<C1>",
    "<C2>",
    "<C3>",
    "<C4>",
    "<C5>",
    "<C6>",
    "<C7>",
    "<C8>",
    "<C9>",
    "<CA>",
    "<CB>",
    "<CC>",
    "<CD>",
    "<CE>",
    "<CF>",
    "<D0>",
    "<D1>",
    "<D2>",
    "<D3>",
    "<D4>",
    "<D5>",
    "<D6>",
    "<D7>",
    "<D8>",
    "<D9>",
    "<DA>",
    "<DB>",
    "<DC>",
    "<DD>",
    "<DE>",
    "<DF>",
    "<E0>",
    "<E1>",
    "<E2>",
    "<E3>",
    "<E4>",
    "<E5>",
    "<E6>",
    "<E7>",
    "<E8>",
    "<E9>",
    "<EA>",
    "<EB>",
    "<EC>",
    "<ED>",
    "<EE>",
    "<EF>",
    "<F0>",
    "<F1>",
    "<F2>",
    "<F3>",
    "<F4>",
    "<F5>",
    "<F6>",
    "<F7>",
    "<F8>",
    "<F9>",
    "<FA>",
    "<FB>",
    "<FC>",
    "<FD>",
    "<FE>",
    "<FF>",
};
