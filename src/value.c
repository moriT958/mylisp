#include "value.h"

#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>

bool value_is_truthy(Value v) {
    return !(is_bool(v) && !as_bool(v));
}

bool values_equal(Value a, Value b) {
    if (a.type != b.type) return false;
    switch (a.type) {
    case VAL_NIL:
        return true;
    case VAL_BOOL:
        return as_bool(a) == as_bool(b);
    case VAL_INT:
        return as_int(a) == as_int(b);
    case VAL_OBJ:
        return as_obj(a) == as_obj(b);
    }
    return false;
}

void value_print(Value v) {
    switch (v.type) {
    case VAL_NIL:
        printf("()");
        break;
    case VAL_BOOL:
        printf(as_bool(v) ? "#t" : "#f");
        break;
    case VAL_INT:
        printf("%" PRId64, as_int(v));
        break;
    case VAL_OBJ:
        // Placeholder: real printing needs the concrete object types, which come with object.h.
        printf("#<object %p>", (void *)as_obj(v));
        break;
    }
}

void value_array_init(ValueArray *array) {
    array->count = 0;
    array->capacity = 0;
    array->values = NULL;
}

// TODO: switch to the GC-aware reallocate() once the heap exists.
void value_array_write(ValueArray *array, Value v) {
    if (array->capacity < array->count + 1) {
        size_t new_capacity = array->capacity < 8 ? 8 : array->capacity * 2;
        Value *grown = realloc(array->values, sizeof(Value) * new_capacity);
        if (grown == NULL) {
            fprintf(stderr, "out of memory\n");
            exit(1);
        }
        array->values = grown;
        array->capacity = new_capacity;
    }
    array->values[array->count++] = v;
}

void value_array_free(ValueArray *array) {
    free(array->values);
    value_array_init(array);
}
