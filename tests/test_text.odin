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

    ignores_bare_cr: {
        text = {};
        defer(e.delete_text(&text));

        data = cast([]u8)"test\rCR";
        ok = e.text_init(&text, data);
        assert(ok);
        assert(text.line_end_style == .LF);
        assert(len(text.lines) == 1);
    }

    handles_ending_on_line: {
        text = {};
        defer(e.delete_text(&text));

        data = cast([]u8)"test\n";
        ok = e.text_init(&text, data);
        assert(ok);
        assert(text.line_end_style == .LF);
        assert(len(text.lines) == 1);
    }

    can_have_CR_with_CRLF: {
        text = {};
        defer(e.delete_text(&text));

        data = cast([]u8)"test\r\nsome\rother\r\ntext\n";
        ok = e.text_init(&text, data);
        assert(ok);
        assert(text.line_end_style == .CRLF);
        assert(len(text.lines) == 3);
    }
}
