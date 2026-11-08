#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"
#include "audio-engine.h"

#include <atomic>
#include <cstring>
#include <mutex>
#ifdef _WIN32
#include <windows.h>
#else
#include <pthread.h>
#endif
#include <vector>

#ifdef _WIN32
#define NEKO_EXPORT extern "C" __declspec(dllexport)
#else
#define NEKO_EXPORT extern "C" __attribute__((visibility("default")))
#endif

namespace {
constexpr uint64_t kCapacity = 48000 * 2;
struct Sink {
  ma_device device{};
  bool initialized = false;
  neko_dsp::AudioEngine engine{48000, 2};
  std::vector<int16_t> ring = std::vector<int16_t>(kCapacity);
  std::atomic<uint64_t> read{0};
  std::atomic<uint64_t> write{0};
  std::atomic<uint64_t> played{0};
  std::atomic<bool> paused{true};
  std::atomic<uint64_t> faults{0};
  std::atomic<float> volume{.75f};
  std::mutex settings_mutex;
  neko_dsp::EffectSettings pending;
  bool changed = false;
};

void release(Sink* sink) {
  ma_device_uninit(&sink->device);
  delete sink;
}

// Runs release() on a detached thread (plain OS APIs: no std::thread so older
// MinGW thread models still link). Returns false when no thread could start.
bool release_async(Sink* sink) {
#ifdef _WIN32
  HANDLE thread = CreateThread(nullptr, 0, [](LPVOID data) -> DWORD {
    release(static_cast<Sink*>(data));
    return 0;
  }, sink, 0, nullptr);
  if (thread == nullptr) return false;
  CloseHandle(thread);
  return true;
#else
  pthread_t thread;
  if (pthread_create(&thread, nullptr, [](void* data) -> void* {
    release(static_cast<Sink*>(data));
    return nullptr;
  }, sink) != 0) return false;
  pthread_detach(thread);
  return true;
#endif
}

void render(Sink* sink, int16_t* destination, ma_uint32 frame_count) {
  if (sink->paused.load(std::memory_order_acquire)) return;
  {
    std::unique_lock<std::mutex> settings(sink->settings_mutex, std::try_to_lock);
    if (settings.owns_lock() && sink->changed) {
      try { sink->engine.configure(sink->pending); } catch (...) {}
      sink->changed = false;
    }
  }
  const uint64_t read = sink->read.load(std::memory_order_relaxed);
  const uint64_t write = sink->write.load(std::memory_order_acquire);
  const auto samples = static_cast<uint32_t>(std::min<uint64_t>(write - read, frame_count * 2));
  for (uint32_t index = 0; index < samples; index++) destination[index] = sink->ring[(read + index) % kCapacity];
  if (samples > 0) {
    sink->engine.process(destination, samples);
    const float volume = sink->volume.load(std::memory_order_relaxed);
    for (uint32_t index = 0; index < samples; index++) destination[index] = static_cast<int16_t>(destination[index] * volume);
    sink->read.store(read + samples, std::memory_order_release);
    sink->played.fetch_add(samples / 2, std::memory_order_relaxed);
  }
}

// An exception escaping the audio thread would call std::terminate; emit
// silence for the buffer and count the fault so Dart can log it.
void callback(ma_device* device, void* output, const void*, ma_uint32 frame_count) {
  auto* sink = static_cast<Sink*>(device->pUserData);
  auto* destination = static_cast<int16_t*>(output);
  std::memset(output, 0, frame_count * 2 * sizeof(int16_t));
  try {
    render(sink, destination, frame_count);
  } catch (...) {
    std::memset(output, 0, frame_count * 2 * sizeof(int16_t));
    sink->read.store(sink->write.load(std::memory_order_acquire), std::memory_order_release);
    sink->faults.fetch_add(1, std::memory_order_relaxed);
  }
}
}

NEKO_EXPORT void* neko_sink_create(int silent) {
  try {
    auto* sink = new Sink();
    if (silent != 0) return sink;
    ma_device_config config = ma_device_config_init(ma_device_type_playback);
    config.playback.format = ma_format_s16;
    config.playback.channels = 2;
    config.sampleRate = 48000;
    config.periodSizeInMilliseconds = 20;
    config.dataCallback = callback;
    config.pUserData = sink;
    if (ma_device_init(nullptr, &config, &sink->device) != MA_SUCCESS) { delete sink; return nullptr; }
    sink->initialized = true;
    if (ma_device_start(&sink->device) != MA_SUCCESS) { ma_device_uninit(&sink->device); delete sink; return nullptr; }
    return sink;
  } catch (...) { return nullptr; }
}

NEKO_EXPORT void neko_sink_destroy(void* handle) {
  auto* sink = static_cast<Sink*>(handle);
  if (sink == nullptr) return;
  if (!sink->initialized) { delete sink; return; }
  // ma_device_uninit joins the audio thread and can block for a while on
  // PulseAudio/WASAPI; keep it off the caller (Dart UI isolate).
  sink->paused.store(true, std::memory_order_release);
  if (!release_async(sink)) release(sink);
}

NEKO_EXPORT uint64_t neko_sink_faults(void* handle) {
  return handle == nullptr ? 0 : static_cast<Sink*>(handle)->faults.load(std::memory_order_relaxed);
}

NEKO_EXPORT int neko_sink_write(void* handle, const int16_t* samples, int count) {
  auto* sink = static_cast<Sink*>(handle);
  if (sink == nullptr || samples == nullptr || count < 0 || count % 2 != 0) return -1;
  const auto write = sink->write.load(std::memory_order_relaxed);
  const auto read = sink->read.load(std::memory_order_acquire);
  const int accepted = static_cast<int>(std::min<uint64_t>(count, kCapacity - (write - read))) & ~1;
  for (int index = 0; index < accepted; index++) sink->ring[(write + index) % kCapacity] = samples[index];
  sink->write.store(write + accepted, std::memory_order_release);
  return accepted;
}

NEKO_EXPORT uint64_t neko_sink_played(void* handle) {
  return handle == nullptr ? 0 : static_cast<Sink*>(handle)->played.load(std::memory_order_relaxed);
}

NEKO_EXPORT int neko_sink_buffered(void* handle) {
  if (handle == nullptr) return 0;
  auto* sink = static_cast<Sink*>(handle);
  const auto read = sink->read.load(std::memory_order_acquire);
  return static_cast<int>(sink->write.load(std::memory_order_acquire) - read);
}

NEKO_EXPORT void neko_sink_pause(void* handle, int paused) {
  if (handle != nullptr) static_cast<Sink*>(handle)->paused.store(paused != 0, std::memory_order_release);
}

NEKO_EXPORT void neko_sink_volume(void* handle, float volume) {
  if (handle != nullptr && std::isfinite(volume)) static_cast<Sink*>(handle)->volume.store(std::clamp(volume, 0.f, 1.f));
}

NEKO_EXPORT int neko_sink_settings(void* handle, const float* values, int count) {
  if (handle == nullptr || values == nullptr || count != 18) return -1;
  for (int index = 0; index < count; index++) if (!std::isfinite(values[index])) return -1;
  const int mastering = static_cast<int>(values[16]);
  if (mastering != 0 && (mastering < 15 || mastering > 34)) return -1;
  auto* sink = static_cast<Sink*>(handle);
  std::lock_guard<std::mutex> lock(sink->settings_mutex);
  for (int index = 0; index < 10; index++) sink->pending.eq[index] = std::clamp(values[index], -15.f, 15.f);
  sink->pending.bass = static_cast<int>(values[10]);
  sink->pending.width = static_cast<int>(values[11]);
  sink->pending.wet = static_cast<int>(values[12]);
  sink->pending.room = static_cast<int>(values[13]);
  sink->pending.damping = static_cast<int>(values[14]);
  sink->pending.loudness = static_cast<int>(values[15]);
  sink->pending.masteringId = mastering;
  sink->pending.masteringMix = static_cast<int>(values[17]);
  sink->changed = true;
  return 0;
}

NEKO_EXPORT int neko_sink_render_test(void* handle, int16_t* output, int frames) {
  if (handle == nullptr || output == nullptr || frames < 0 || frames > 48000 || static_cast<Sink*>(handle)->initialized) return -1;
  ma_device device{};
  device.pUserData = handle;
  callback(&device, output, nullptr, frames);
  return 0;
}
