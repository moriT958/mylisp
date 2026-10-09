#ifndef MYLISP_VALUE_H
#define MYLISP_VALUE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// Forward declarations: object.h and vm.h include this header, so including them here would be circular.
typedef struct Obj Obj;
typedef struct VM VM;

typedef enum {
    VAL_NIL,
    VAL_BOOL,
    VAL_INT,
    VAL_OBJ,
} ValueType;

typedef struct {
    ValueType type;
    union {
        bool boolean;
        int64_t integer;
        Obj *obj;
    } as;
} Value;

static inline Value val_nil(void) { return (Value){VAL_NIL, {.integer = 0}}; }
static inline Value val_bool(bool b) { return (Value){VAL_BOOL, {.boolean = b}}; }
static inline Value val_int(int64_t n) { return (Value){VAL_INT, {.integer = n}}; }
static inline Value val_obj(Obj *o) { return (Value){VAL_OBJ, {.obj = o}}; }

static inline bool is_nil(Value v) { return v.type == VAL_NIL; }
static inline bool is_bool(Value v) { return v.type == VAL_BOOL; }
static inline bool is_int(Value v) { return v.type == VAL_INT; }
static inline bool is_obj(Value v) { return v.type == VAL_OBJ; }

static inline bool as_bool(Value v) { return v.as.boolean; }
static inline int64_t as_int(Value v) { return v.as.integer; }
static inline Obj *as_obj(Value v) { return v.as.obj; }

// Unlike C, only #f is false: nil and 0 are true.
bool value_is_truthy(Value v);

// eq? semantics: objects compare by identity.
bool values_equal(Value a, Value b);

void value_print(Value v);

typedef struct {
    size_t count;
    size_t capacity;
    Value *values;
} ValueArray;

void value_array_init(ValueArray *array);
void value_array_write(VM *vm, ValueArray *array, Value v);
void value_array_free(VM *vm, ValueArray *array);

#endif
