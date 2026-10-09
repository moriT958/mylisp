#include "value.h"

#include <inttypes.h>
#include <stdio.h>

#include "memory.h"
#include "object.h"

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
        object_print(v);
        break;
    }
}

void value_array_init(ValueArray *array) {
    array->count = 0;
    array->capacity = 0;
    array->values = NULL;
}

void value_array_write(VM *vm, ValueArray *array, Value v) {
    if (array->capacity < array->count + 1) {
        size_t old_capacity = array->capacity;
        array->capacity = grow_capacity(old_capacity);
        array->values = GROW_ARRAY(vm, Value, array->values, old_capacity, array->capacity);
    }
    array->values[array->count++] = v;
}

void value_array_free(VM *vm, ValueArray *array) {
    FREE_ARRAY(vm, Value, array->values, array->capacity);
    value_array_init(array);
}
