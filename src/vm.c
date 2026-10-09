#include "vm.h"

#include <assert.h>
#include <stdarg.h>
#include <stdio.h>

#include "object.h"

#ifdef DEBUG_TRACE_EXECUTION
#include "debug.h"
#endif

static void reset_stack(VM *vm) {
    vm->stack_top = vm->stack;
}

void vm_init(VM *vm) {
    vm->chunk = NULL;
    vm->ip = NULL;
    vm->bytes_allocated = 0;
    vm->objects = NULL;
    reset_stack(vm);
}

void vm_free(VM *vm) {
    object_free_all(vm);
}

static InterpretResult runtime_error(const char *format, ...) {
    va_list args;
    va_start(args, format);
    fprintf(stderr, "runtime error: ");
    vfprintf(stderr, format, args);
    fprintf(stderr, "\n");
    va_end(args);
    return INTERPRET_RUNTIME_ERROR;
}

static bool push(VM *vm, Value value) {
    if (vm->stack_top == vm->stack + STACK_MAX) return false;
    *vm->stack_top++ = value;
    return true;
}

// Well-formed bytecode never underflows; the assert catches compiler bugs.
static Value pop(VM *vm) {
    assert(vm->stack_top > vm->stack);
    return *--vm->stack_top;
}

static inline uint8_t read_byte(VM *vm) {
    return *vm->ip++;
}

static inline Value read_constant(VM *vm) {
    return vm->chunk->constants.values[read_byte(vm)];
}

// Signed overflow is undefined in C, so it must be detected. The builtins
// cannot be passed as function pointers, hence the wrappers.
static bool add_overflows(int64_t a, int64_t b, int64_t *out) {
    return __builtin_add_overflow(a, b, out);
}

static bool sub_overflows(int64_t a, int64_t b, int64_t *out) {
    return __builtin_sub_overflow(a, b, out);
}

static bool mul_overflows(int64_t a, int64_t b, int64_t *out) {
    return __builtin_mul_overflow(a, b, out);
}

// The push cannot fail: two slots were just freed.
static InterpretResult binary_op(VM *vm, bool (*overflows)(int64_t, int64_t, int64_t *)) {
    Value b = pop(vm);
    Value a = pop(vm);
    if (!is_int(a) || !is_int(b)) return runtime_error("operands must be integers");
    int64_t out;
    if (overflows(as_int(a), as_int(b), &out)) return runtime_error("integer overflow");
    push(vm, val_int(out));
    return INTERPRET_OK;
}

static InterpretResult divide(VM *vm) {
    Value b = pop(vm);
    Value a = pop(vm);
    if (!is_int(a) || !is_int(b)) return runtime_error("operands must be integers");
    if (as_int(b) == 0) return runtime_error("division by zero");
    // INT64_MIN / -1 overflows, which is undefined in C.
    if (as_int(a) == INT64_MIN && as_int(b) == -1) return runtime_error("integer overflow");
    push(vm, val_int(as_int(a) / as_int(b)));
    return INTERPRET_OK;
}

static InterpretResult run(VM *vm, Value *result) {
    for (;;) {
#ifdef DEBUG_TRACE_EXECUTION
        printf("          ");
        for (const Value *slot = vm->stack; slot < vm->stack_top; slot++) {
            printf("[ ");
            value_print(*slot);
            printf(" ]");
        }
        printf("\n");
        disassemble_instruction(vm->chunk, (size_t)(vm->ip - vm->chunk->code));
#endif
        uint8_t instruction = read_byte(vm);
        InterpretResult status = INTERPRET_OK;
        switch (instruction) {
        case OP_CONST:
            if (!push(vm, read_constant(vm))) status = runtime_error("stack overflow");
            break;
        case OP_ADD:
            status = binary_op(vm, add_overflows);
            break;
        case OP_SUB:
            status = binary_op(vm, sub_overflows);
            break;
        case OP_MUL:
            status = binary_op(vm, mul_overflows);
            break;
        case OP_DIV:
            status = divide(vm);
            break;
        case OP_RETURN:
            *result = pop(vm);
            return INTERPRET_OK;
        default:
            status = runtime_error("unknown opcode %u", instruction);
            break;
        }
        if (status != INTERPRET_OK) return status;
    }
}

// Reset every call so an earlier error leaves no stale values; the REPL reuses one VM.
InterpretResult vm_interpret(VM *vm, const Chunk *chunk, Value *result) {
    reset_stack(vm);
    vm->chunk = chunk;
    vm->ip = chunk->code;
    return run(vm, result);
}
