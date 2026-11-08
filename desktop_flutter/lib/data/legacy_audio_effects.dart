import '../i18n/tr.dart';
import '../domain/audio_effects.dart';
import '../domain/mastering_presets.dart';

class LegacyAudioEffects {
  static const _keys = {
    'eq_bands',
    'eq_preset',
    'bass_boost',
    'virtualizer',
    'reverb_wet',
    'reverb_room_size',
    'reverb_damping',
    'loudness_gain',
    'mastering_preset_id',
    'mastering_mix',
  };

  static AudioEffects? parse(Map<String, String> values) {
    if (!values.keys.any(_keys.contains)) return null;

    double number(String key, double fallback) {
      final raw = values[key];
      if (raw == null) return fallback;
      final value = double.tryParse(raw);
      if (value == null || !value.isFinite || value < 0 || value > 100) {
        throw FormatException(tr('旧版音效参数 {key} 超出范围（0–100）。', {'key': key}));
      }
      return value;
    }

    var bands = const AudioEffects().eq;
    final presetName = values['eq_preset'];
    final rawBands = values['eq_bands'];
    if (rawBands == null && presetName != null && presetName.isNotEmpty) {
      final preset = AudioEffects.presets[presetName];
      if (preset == null) {
        throw       FormatException(tr('旧版均衡器预设不存在，未导入音效。'));
      }
      bands = List<double>.of(preset);
    }
    if (rawBands != null) {
      final parsed = rawBands.split(',').map(double.tryParse).toList();
      if (parsed.length != 10 ||
          parsed.any(
            (value) =>
                value == null || !value.isFinite || value < -15 || value > 15,
          )) {
        throw       FormatException(tr('旧版均衡器必须包含 10 段有限数值（−15–15 dB）。'));
      }
      bands = parsed.cast<double>();
    }
    final rawMastering = values['mastering_preset_id'];
    final mastering = rawMastering == null ? 0 : int.tryParse(rawMastering);
    if (mastering == null ||
        mastering != 0 && MasteringPreset.find(mastering) == null) {
      throw       FormatException(tr('旧版母带预设未实现或无效，未导入音效；请在旧版关闭母带后重试。'));
    }
    return AudioEffects(
      eq: bands,
      bass: number('bass_boost', 0),
      width: number('virtualizer', 0),
      wet: number('reverb_wet', 0),
      room: number('reverb_room_size', 50),
      damping: number('reverb_damping', 30),
      loudness: number('loudness_gain', 0),
      mastering: mastering,
      mix: number('mastering_mix', 100),
    );
  }
}
