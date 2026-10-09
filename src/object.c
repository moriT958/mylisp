#include "object.h"

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

static void free_object(VM *vm, Obj *object) {
    switch (object->type) {
    case OBJ_PAIR:
        reallocate(vm, object, sizeof(ObjPair), 0);
        break;
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
