package stack

import "core:mem"


// ReverseStack is probably not a good/correct name for this.
//
// This is essentially a dynamic array whose data is copied into and out
// of the end of the memory buffer so that pushing 3 and popping 3 have the
// same memory representation without having to reverse after popping
//
// push_rs(stack, [1, 2, 3])
// push_rs(stack, 4)
// push_rs(stack, 5)
// would be placed in memory as 5 4 1 2 3
//        data added here -----^         ^--- Ends here (this would be index 0)
// pop_rs(stack, 3)
// would return [5, 4, 1];

ReverseStack :: struct(Type: typeid) {
    data: ^Type,
    len: int,
    cap: int,
    allocator: mem.Allocator,
}


push_rs :: proc(stack: ^$T/ReverseStack, args: ..T.Type, loc := #caller_location) {
    if stack == nil do return;

    arg_len := len(args);
    if arg_len == 0 do return;

    assert(stack != nil);
    array := (^[dynamic]T.Type)(stack);
    if cap(array) <= len(array)+arg_len {
        old_cap := cap(array);
        new_cap := 2 * cap(array) + max(8, arg_len);
        _ = reserve(array, new_cap, loc);
        if old_cap > 0 {
            // Since this grows backwards, this memory needs to be in the correct spot
            mem.copy(mem.ptr_offset(stack.data, (stack.cap - old_cap) * size_of(T.Type)),
                     stack.data,
                     old_cap * size_of(T.Type));
        }
    }

    mem.copy(mem.ptr_offset(stack.data, (stack.cap - stack.len - arg_len) * size_of(T.Type)),
             &args[0],
             size_of(T.Type) * arg_len);
    stack.len += arg_len;
}


pop_rs :: proc(stack: ^$T/ReverseStack, count: int, allocator := context.temp_allocator) -> []T.Type {
    assert(stack.len >= count);

    result := make([]T.Type, count, allocator);
    if count == 0 do return result;

    mem.copy(&result[0], mem.ptr_offset(stack.data, stack.cap - stack.len), count * size_of(T.Type));
    stack.len -= count;

    return result;
}


peek_rs :: proc(stack: ^$T/ReverseStack, count: int, allocator := context.temp_allocator) -> []T.Type {
    result := make([]T.Type, count, allocator);
    mem.copy(&result[0], mem.ptr_offset(stack.data, stack.cap - stack.len), count * size_of(T.Type));
    return result;
}


delete_rs :: proc(stack: $T/ReverseStack, allocator := context.allocator, loc := #caller_location) {
    delete(transmute([dynamic]T.Type)(stack));
}


make_rs :: proc($T: typeid, allocator := context.allocator, loc := #caller_location) -> T {
    return transmute(T)make([dynamic]T.Type, allocator, loc);
}

make_rs_len :: proc($T: typeid, auto_cast len: int, allocator := context.allocator, loc := #caller_location) -> T {
    return transmute(T)make([dynamic]T.Type, len, allocator, loc);
}

make_rs_len_cap :: proc($T: typeid, auto_cast len: int, auto_cast cap: int, allocator := context.allocator, loc := #caller_location) -> T {
    return transmute(T)make([dynamic]T.Type, len, cap, allocator, loc);
}

make_reverse_stack :: proc{make_rs, make_rs_len, make_rs_len_cap};
