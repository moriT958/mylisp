#ifndef MYLISP_TABLE_H
#define MYLISP_TABLE_H

#include "object.h"
#include "value.h"

typedef struct {
    ObjSymbol *key;
    Value value;
} Entry;

// Open addressing with linear probing. There is no delete: symbols are never
// freed individually, so tombstones would only add complexity.
typedef struct {
    size_t count;
    size_t capacity;
    Entry *entries;
} Table;

void table_init(Table *table);
void table_free(VM *vm, Table *table);

bool table_get(const Table *table, const ObjSymbol *key, Value *value);

// Returns true if the key is new.
bool table_set(VM *vm, Table *table, ObjSymbol *key, Value value);

// Finds a symbol by content, which interning needs before a key object exists.
ObjSymbol *table_find_symbol(const Table *table, const char *chars, size_t length, uint32_t hash);

#endif
