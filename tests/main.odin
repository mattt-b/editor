package test

import "core:runtime"
import "core:time"
import "core:fmt"

foreign import libc "system:c"

JmpBuf :: [200]u8;

foreign libc {
    setjmp :: proc(env: ^JmpBuf) -> int ---;
    longjmp :: proc(env: ^JmpBuf, val: int) ---;
}


tests := [?]Test{
    {"test_init_text_line_endings", test_init_text_line_endings},
};

Test :: struct {
    name: string,
    procedure: proc(),
}

jmp_buf: JmpBuf;

Failure :: struct {
    test: string,
    prefix: string,
    message: string,
    loc: runtime.Source_Code_Location,
}

failures: [dynamic]Failure;

test_assertion_proc :: proc(prefix, message: string, loc: runtime.Source_Code_Location) {
    append(&failures, Failure{prefix=prefix, message=message, loc=loc});
    longjmp(&jmp_buf, 1);
}

main :: proc() {
    start_time := time.now();

    context.assertion_failure_proc = test_assertion_proc;

    fmt.println();

    passed := 0;
    failed := 0;
    for test in tests {
        if (!bool(setjmp(&jmp_buf))) {
            test.procedure();
            passed += 1;
            fmt.printf("\e[92m.\e[0m");
        } else {
            failures[len(failures)-1].test = test.name;
            fmt.printf("\e[91m!\e[0m");
            failed += 1;
        }
    }

    fmt.println();
    fmt.println();

    for failure, i in failures {
        fmt.printf("%v) %v\n", i + 1, failure.test);
        fmt.println();
        fmt.printf("\e[91m");
        fmt.printf("\t%v: %v\n", failure.prefix, failure.message);
        fmt.println();
        fmt.printf("\t%v\n", failure.loc.procedure);
        fmt.printf("\t%v:%v:%v\n",
                   failure.loc.file_path, failure.loc.line, failure.loc.column);
        fmt.println();
        fmt.printf("\e[0m");
    }

    fmt.println();
    fmt.println("Passed: ", passed);
    fmt.println("Failed: ", failed);

    end_time := time.now();
    took := time.duration_seconds(time.diff(start_time, end_time));
    fmt.println_err("Took: ", took);
}
