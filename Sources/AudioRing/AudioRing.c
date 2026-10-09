#include "AudioRing.h"

#include <math.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

#define BANDS 4

struct AudioRing {
    float *data;
    uint32_t capacity;
    _Atomic uint64_t head;
    _Atomic uint64_t tail;
    _Atomic bool flush_requested;
    _Atomic uint64_t rendered;

    float coeff[BANDS - 1];
    float state[BANDS - 1];
    _Atomic float level[BANDS];
};

AudioRing *audio_ring_create(uint32_t capacity_frames, double sample_rate) {
    AudioRing *ring = calloc(1, sizeof(AudioRing));
    if (!ring) return NULL;
    ring->data = calloc((size_t)capacity_frames * 2, sizeof(float));
    if (!ring->data) {
        free(ring);
        return NULL;
    }
    ring->capacity = capacity_frames;
    const double cutoffs[BANDS - 1] = {150.0, 600.0, 2500.0};
    for (int i = 0; i < BANDS - 1; i++) {
        ring->coeff[i] = (float)(1.0 - exp(-2.0 * M_PI * cutoffs[i] / sample_rate));
    }
    return ring;
}

void audio_ring_destroy(AudioRing *ring) {
    if (!ring) return;
    free(ring->data);
    free(ring);
}

uint32_t audio_ring_write(AudioRing *ring, const float *interleaved, uint32_t frames) {
    uint64_t head = atomic_load_explicit(&ring->head, memory_order_relaxed);
    uint64_t tail = atomic_load_explicit(&ring->tail, memory_order_acquire);
    uint32_t free_frames = ring->capacity - (uint32_t)(head - tail);
    uint32_t n = frames < free_frames ? frames : free_frames;
    if (n == 0) return 0;

    uint32_t start = (uint32_t)(head % ring->capacity);
    uint32_t first = ring->capacity - start;
    if (first > n) first = n;
    memcpy(ring->data + (size_t)start * 2, interleaved, (size_t)first * 2 * sizeof(float));
    if (n > first) {
        memcpy(ring->data, interleaved + (size_t)first * 2, (size_t)(n - first) * 2 * sizeof(float));
    }
    atomic_store_explicit(&ring->head, head + n, memory_order_release);
    return n;
}

uint32_t audio_ring_render(AudioRing *ring, float *left, float *right, uint32_t frames) {
    uint64_t tail = atomic_load_explicit(&ring->tail, memory_order_relaxed);
    uint64_t head = atomic_load_explicit(&ring->head, memory_order_acquire);

    if (atomic_exchange_explicit(&ring->flush_requested, false, memory_order_acq_rel)) {
        tail = head;
        atomic_store_explicit(&ring->tail, tail, memory_order_release);
    }

    uint32_t available = (uint32_t)(head - tail);
    uint32_t n = frames < available ? frames : available;

    float sum[BANDS] = {0, 0, 0, 0};
    float s0 = ring->state[0], s1 = ring->state[1], s2 = ring->state[2];
    const float c0 = ring->coeff[0], c1 = ring->coeff[1], c2 = ring->coeff[2];

    for (uint32_t i = 0; i < n; i++) {
        uint32_t index = (uint32_t)((tail + i) % ring->capacity) * 2;
        float l = ring->data[index];
        float r = ring->data[index + 1];
        left[i] = l;
        right[i] = r;

// Bands from cascaded one-pole low-passes at 150 / 600 / 2500 Hz.
        float mono = 0.5f * (l + r);
        s0 += c0 * (mono - s0);
        s1 += c1 * (mono - s1);
        s2 += c2 * (mono - s2);
        float b0 = s0, b1 = s1 - s0, b2 = s2 - s1, b3 = mono - s2;
        sum[0] += b0 * b0;
        sum[1] += b1 * b1;
        sum[2] += b2 * b2;
        sum[3] += b3 * b3;
    }
    ring->state[0] = s0;
    ring->state[1] = s1;
    ring->state[2] = s2;

    if (n < frames) {
        memset(left + n, 0, (size_t)(frames - n) * sizeof(float));
        memset(right + n, 0, (size_t)(frames - n) * sizeof(float));
    }
    if (n > 0) {
        atomic_store_explicit(&ring->tail, tail + n, memory_order_release);
        atomic_fetch_add_explicit(&ring->rendered, n, memory_order_relaxed);
    }

    for (int b = 0; b < BANDS; b++) {
        float rms = n > 0 ? sqrtf(sum[b] / (float)n) : 0.0f;
        float previous = atomic_load_explicit(&ring->level[b], memory_order_relaxed);
        float next = rms > previous ? rms : previous * 0.88f + rms * 0.12f;
        atomic_store_explicit(&ring->level[b], next, memory_order_relaxed);
    }
    return n;
}

void audio_ring_request_flush(AudioRing *ring) {
    atomic_store_explicit(&ring->flush_requested, true, memory_order_release);
}

void audio_ring_levels(const AudioRing *ring, float out_levels[4]) {
    for (int b = 0; b < BANDS; b++) {
        out_levels[b] = atomic_load_explicit(&((AudioRing *)ring)->level[b], memory_order_relaxed);
    }
}

uint64_t audio_ring_rendered_frames(const AudioRing *ring) {
    return atomic_load_explicit(&((AudioRing *)ring)->rendered, memory_order_relaxed);
}
