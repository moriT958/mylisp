#ifndef MYLISP_OBJECT_H
#define MYLISP_OBJECT_H

#include "value.h"

typedef enum {
    OBJ_PAIR,
} ObjType;

// Every object struct starts with this header so an Obj* can stand for any of them.
struct Obj {
    ObjType type;
    struct Obj *next;
};

typedef struct {
    Obj obj;
    Value car;
    Value cdr;
} ObjPair;

ObjPair *pair_new(VM *vm, Value car, Value cdr);

static inline bool is_pair(Value v) { return is_obj(v) && as_obj(v)->type == OBJ_PAIR; }
static inline ObjPair *as_pair(Value v) { return (ObjPair *)as_obj(v); }
static inline Value val_pair(ObjPair *pair) { return val_obj(&pair->obj); }

void object_free_all(VM *vm);

#endif
