#ifndef AUDIO_RING_H
#define AUDIO_RING_H

#include <stdint.h>
#include <stdbool.h>

// Lock-free single-producer/single-consumer ring buffer for interleaved stereo float audio,
// plus a 4-band level analysis for the menu bar visualizer.
// audio_ring_render() runs on the CoreAudio real-time thread: no locks, no allocations.
typedef struct AudioRing AudioRing;

AudioRing *audio_ring_create(uint32_t capacity_frames, double sample_rate);
void audio_ring_destroy(AudioRing *ring);

uint32_t audio_ring_write(AudioRing *ring, const float *interleaved, uint32_t frames);

uint32_t audio_ring_render(AudioRing *ring, float *left, float *right, uint32_t frames);

void audio_ring_request_flush(AudioRing *ring);

void audio_ring_levels(const AudioRing *ring, float out_levels[4]);

uint64_t audio_ring_rendered_frames(const AudioRing *ring);

#endif
