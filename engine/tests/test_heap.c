#include <stdlib.h>

#include "heap.h"
#include "testutil.h"

static int cmp_double(const void *a, const void *b)
{
    double x = *(const double *)a, y = *(const double *)b;
    return (x > y) - (x < y);
}

static void test_empty(void)
{
    MinHeap h;
    HeapItem it;
    CHECK(heap_init(&h, 4) == 0);
    CHECK(heap_empty(&h));
    CHECK(!heap_pop(&h, &it));
    heap_free(&h);
}

static void test_pops_in_priority_order(void)
{
    MinHeap h;
    HeapItem it;
    const double prios[] = {5, 3, 8, 1, 9, 2, 7};
    const double sorted[] = {1, 2, 3, 5, 7, 8, 9};
    CHECK(heap_init(&h, 0) == 0); /* 0 means "use the default capacity" */
    for (int i = 0; i < 7; i++)
        CHECK(heap_push(&h, i, prios[i]) == 0);
    for (int i = 0; i < 7; i++) {
        CHECK(heap_pop(&h, &it));
        CHECK(it.prio == sorted[i]);
    }
    CHECK(heap_empty(&h));
    heap_free(&h);
}

static void test_node_travels_with_priority(void)
{
    MinHeap h;
    HeapItem it;
    CHECK(heap_init(&h, 2) == 0);
    heap_push(&h, 10, 3.0);
    heap_push(&h, 20, 1.0);
    heap_push(&h, 30, 2.0);
    CHECK(heap_pop(&h, &it) && it.node == 20);
    CHECK(heap_pop(&h, &it) && it.node == 30);
    CHECK(heap_pop(&h, &it) && it.node == 10);
    heap_free(&h);
}

static void test_duplicates_and_equal_priorities(void)
{
    MinHeap h;
    HeapItem it;
    CHECK(heap_init(&h, 4) == 0);
    /* The same node pushed twice with different priorities, as lazy deletion does. */
    heap_push(&h, 7, 4.0);
    heap_push(&h, 7, 2.0);
    heap_push(&h, 8, 2.0);
    CHECK(heap_pop(&h, &it) && it.prio == 2.0);
    CHECK(heap_pop(&h, &it) && it.prio == 2.0);
    CHECK(heap_pop(&h, &it) && it.prio == 4.0 && it.node == 7);
    CHECK(!heap_pop(&h, &it));
    heap_free(&h);
}

static void test_grows_past_initial_capacity(void)
{
    MinHeap h;
    HeapItem it;
    CHECK(heap_init(&h, 1) == 0);
    for (int i = 1000; i > 0; i--)
        CHECK(heap_push(&h, i, (double)i) == 0);
    CHECK(h.size == 1000);
    for (int i = 1; i <= 1000; i++) {
        CHECK(heap_pop(&h, &it));
        CHECK(it.node == i);
    }
    heap_free(&h);
}

static void test_random_matches_qsort(void)
{
    enum { N = 20000 };
    double *vals = malloc(N * sizeof *vals);
    MinHeap h;
    HeapItem it;
    CHECK(vals != NULL && heap_init(&h, 8) == 0);
    srand(12345);
    for (int i = 0; i < N; i++) {
        vals[i] = (double)rand() / RAND_MAX * 1000.0;
        heap_push(&h, i, vals[i]);
    }
    qsort(vals, N, sizeof *vals, cmp_double);
    for (int i = 0; i < N; i++) {
        CHECK(heap_pop(&h, &it));
        CHECK(it.prio == vals[i]);
    }
    CHECK(heap_empty(&h));
    heap_free(&h);
    free(vals);
}

static void test_interleaved_push_pop(void)
{
    MinHeap h;
    HeapItem it;
    CHECK(heap_init(&h, 4) == 0);
    heap_push(&h, 1, 5.0);
    heap_push(&h, 2, 3.0);
    CHECK(heap_pop(&h, &it) && it.prio == 3.0);
    heap_push(&h, 3, 1.0);
    heap_push(&h, 4, 4.0);
    CHECK(heap_pop(&h, &it) && it.prio == 1.0);
    CHECK(heap_pop(&h, &it) && it.prio == 4.0);
    CHECK(heap_pop(&h, &it) && it.prio == 5.0);
    CHECK(!heap_pop(&h, &it));
    heap_free(&h);
}

int main(void)
{
    test_empty();
    test_pops_in_priority_order();
    test_node_travels_with_priority();
    test_duplicates_and_equal_priorities();
    test_grows_past_initial_capacity();
    test_random_matches_qsort();
    test_interleaved_push_pop();
    return TEST_RESULT();
}
