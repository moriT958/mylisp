#include "table.h"

#include <string.h>

#include "memory.h"

void table_init(Table *table) {
    table->count = 0;
    table->capacity = 0;
    table->entries = NULL;
}

void table_free(VM *vm, Table *table) {
    FREE_ARRAY(vm, Entry, table->entries, table->capacity);
    table_init(table);
}

// Capacity is always a power of two, so masking replaces the modulo.
static Entry *find_entry(Entry *entries, size_t capacity, const ObjSymbol *key) {
    size_t index = key->hash & (capacity - 1);
    for (;;) {
        Entry *entry = &entries[index];
        if (entry->key == key || entry->key == NULL) return entry;
        index = (index + 1) & (capacity - 1);
    }
}

static void adjust_capacity(VM *vm, Table *table, size_t capacity) {
    Entry *entries = GROW_ARRAY(vm, Entry, NULL, 0, capacity);
    for (size_t i = 0; i < capacity; i++) {
        entries[i].key = NULL;
        entries[i].value = val_nil();
    }

    for (size_t i = 0; i < table->capacity; i++) {
        Entry *old = &table->entries[i];
        if (old->key == NULL) continue;
        *find_entry(entries, capacity, old->key) = *old;
    }

    FREE_ARRAY(vm, Entry, table->entries, table->capacity);
    table->entries = entries;
    table->capacity = capacity;
}

bool table_get(const Table *table, const ObjSymbol *key, Value *value) {
    if (table->count == 0) return false;
    Entry *entry = find_entry(table->entries, table->capacity, key);
    if (entry->key == NULL) return false;
    *value = entry->value;
    return true;
}

bool table_set(VM *vm, Table *table, ObjSymbol *key, Value value) {
    // Keep the load factor at or below 3/4 so probing always finds an empty slot.
    if (table->count + 1 > table->capacity * 3 / 4) {
        adjust_capacity(vm, table, grow_capacity(table->capacity));
    }

    Entry *entry = find_entry(table->entries, table->capacity, key);
    bool is_new = entry->key == NULL;
    if (is_new) table->count++;
    entry->key = key;
    entry->value = value;
    return is_new;
}

ObjSymbol *table_find_symbol(const Table *table, const char *chars, size_t length, uint32_t hash) {
    if (table->count == 0) return NULL;

    size_t index = hash & (table->capacity - 1);
    for (;;) {
        Entry *entry = &table->entries[index];
        if (entry->key == NULL) return NULL;
        if (entry->key->hash == hash && entry->key->length == length &&
            memcmp(entry->key->chars, chars, length) == 0) {
            return entry->key;
        }
        index = (index + 1) & (table->capacity - 1);
    }
}
