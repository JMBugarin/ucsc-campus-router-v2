#include "heap.h"

#include <stdlib.h>

int heap_init(MinHeap *h, size_t initial_cap)
{
    if (initial_cap == 0)
        initial_cap = 16;
    h->items = malloc(initial_cap * sizeof *h->items);
    h->size = 0;
    h->cap = h->items ? initial_cap : 0;
    return h->items ? 0 : -1;
}

void heap_free(MinHeap *h)
{
    free(h->items);
    h->items = NULL;
    h->size = h->cap = 0;
}

bool heap_empty(const MinHeap *h) { return h->size == 0; }

static void sift_up(MinHeap *h, size_t i)
{
    HeapItem item = h->items[i];
    while (i > 0) {
        size_t parent = (i - 1) / 2;
        if (h->items[parent].prio <= item.prio)
            break;
        h->items[i] = h->items[parent];
        i = parent;
    }
    h->items[i] = item;
}

static void sift_down(MinHeap *h, size_t i)
{
    HeapItem item = h->items[i];
    for (;;) {
        size_t child = 2 * i + 1;
        if (child >= h->size)
            break;
        if (child + 1 < h->size && h->items[child + 1].prio < h->items[child].prio)
            child++;
        if (item.prio <= h->items[child].prio)
            break;
        h->items[i] = h->items[child];
        i = child;
    }
    h->items[i] = item;
}

int heap_push(MinHeap *h, int32_t node, double prio)
{
    if (h->size == h->cap) {
        size_t new_cap = h->cap ? h->cap * 2 : 16;
        HeapItem *grown = realloc(h->items, new_cap * sizeof *grown);
        if (!grown)
            return -1;
        h->items = grown;
        h->cap = new_cap;
    }
    h->items[h->size].node = node;
    h->items[h->size].prio = prio;
    sift_up(h, h->size++);
    return 0;
}

bool heap_pop(MinHeap *h, HeapItem *out)
{
    if (h->size == 0)
        return false;
    *out = h->items[0];
    h->items[0] = h->items[--h->size];
    if (h->size > 0)
        sift_down(h, 0);
    return true;
}
