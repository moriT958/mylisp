#include "object.h"

#include <stdio.h>
#include <string.h>

#include "memory.h"
#include "vm.h"  // IWYU pragma: keep

static Obj *allocate_object(VM *vm, size_t size, ObjType type) {
    Obj *object = reallocate(vm, NULL, 0, size);
    object->type = type;
    object->next = vm->objects;
    vm->objects = object;
    return object;
}

ObjPair *pair_new(VM *vm, Value car, Value cdr) {
    ObjPair *pair = (ObjPair *)allocate_object(vm, sizeof(ObjPair), OBJ_PAIR);
    pair->car = car;
    pair->cdr = cdr;
    return pair;
}

ObjString *string_new(VM *vm, const char *chars, size_t length) {
    ObjString *string =
        (ObjString *)allocate_object(vm, sizeof(ObjString) + length + 1, OBJ_STRING);
    string->length = length;
    memcpy(string->chars, chars, length);
    string->chars[length] = '\0';
    return string;
}

static void print_string(const ObjString *string) {
    putchar('"');
    for (size_t i = 0; i < string->length; i++) {
        char c = string->chars[i];
        if (c == '"' || c == '\\') putchar('\\');
        putchar(c);
    }
    putchar('"');
}

// Walks the cdr chain iteratively so a long list does not recurse once per element.
static void print_list(const ObjPair *pair) {
    putchar('(');
    value_print(pair->car);
    Value rest = pair->cdr;
    while (is_pair(rest)) {
        putchar(' ');
        value_print(as_pair(rest)->car);
        rest = as_pair(rest)->cdr;
    }
    if (!is_nil(rest)) {
        printf(" . ");
        value_print(rest);
    }
    putchar(')');
}

void object_print(Value v) {
    switch (as_obj(v)->type) {
    case OBJ_PAIR:
        print_list(as_pair(v));
        break;
    case OBJ_STRING:
        print_string(as_string(v));
        break;
    }
}

static void free_object(VM *vm, Obj *object) {
    switch (object->type) {
    case OBJ_PAIR:
        reallocate(vm, object, sizeof(ObjPair), 0);
        break;
    case OBJ_STRING: {
        ObjString *string = (ObjString *)object;
        reallocate(vm, object, sizeof(ObjString) + string->length + 1, 0);
        break;
    }
    }
}

void object_free_all(VM *vm) {
    Obj *object = vm->objects;
    while (object != NULL) {
        Obj *next = object->next;
        free_object(vm, object);
        object = next;
    }
    vm->objects = NULL;
}
