#ifndef HEAP_H
#define HEAP_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct {
    int32_t node;
    double prio;
} HeapItem;

/* Binary min-heap keyed on prio. There is no decrease-key: callers push a new
 * entry when a better priority is found and skip stale entries when popped
 * (lazy deletion). */
typedef struct {
    HeapItem *items;
    size_t size, cap;
} MinHeap;

/* Returns 0 on success, -1 if allocation fails. */
int heap_init(MinHeap *h, size_t initial_cap);
void heap_free(MinHeap *h);
int heap_push(MinHeap *h, int32_t node, double prio);
/* Removes the smallest item into *out. Returns false if the heap is empty. */
bool heap_pop(MinHeap *h, HeapItem *out);
bool heap_empty(const MinHeap *h);

#endif
