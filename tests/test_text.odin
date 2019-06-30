package test

import e "../src"


test_init_text_line_endings :: proc() {
    text: e.Text;
    data: []u8;
    ok: bool;

    defaults_to_lf: {
        text = {};
        defer(e.delete_text(&text));
        data = cast([]u8)"test";
        ok = e.text_init(&text, data);
        assert(ok);
        assert(text.line_end_style == .LF);
    }

    uses_lf_when_present: {
        text = {};
        defer(e.delete_text(&text));

        data = cast([]u8)"test\nLF";
        ok = e.text_init(&text, data);
        assert(ok);
        assert(text.line_end_style == .LF);
    }

    uses_crlf_when_present: {
        text = {};
        defer(e.delete_text(&text));

        data = cast([]u8)"test\r\nCRLF";
        ok = e.text_init(&text, data);
        assert(ok);
        assert(text.line_end_style == .CRLF);
    }
}
