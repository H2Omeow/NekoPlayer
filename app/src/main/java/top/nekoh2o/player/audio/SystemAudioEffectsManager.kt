package top.nekoh2o.player.audio

import top.nekoh2o.player.i18n.NekoI18n.tr

import android.media.audiofx.AudioEffect
import android.media.audiofx.BassBoost
import android.media.audiofx.Equalizer
import android.media.audiofx.LoudnessEnhancer
import android.media.audiofx.PresetReverb
import android.media.audiofx.Virtualizer
import android.util.Log
import top.nekoh2o.player.data.model.AudioEffectSettings
import top.nekoh2o.player.data.model.EQPresets
import kotlin.math.ln

class SystemAudioEffectsManager(private val audioSessionId: Int) {
    private var equalizer: Equalizer? = null
    private var bassBoost: BassBoost? = null
    private var virtualizer: Virtualizer? = null
    private var loudness: LoudnessEnhancer? = null
    private var reverb: PresetReverb? = null
    val auxEffectId: Int get() = runCatching { reverb?.id ?: 0 }.getOrDefault(0)
    var reverbSendLevel: Float = 0f
        private set

    var capabilities = SystemEffectCapabilities()
        private set

    fun initialize(): Boolean {
        release(publish = false)
        if (audioSessionId <= 0) return false
        equalizer = createEffect(tr("均衡器"), { Equalizer(0, audioSessionId) }) {
            check(it.numberOfBands > 0 && it.bandLevelRange.size >= 2)
            check(it.setEnabled(true) == AudioEffect.SUCCESS)
        }
        bassBoost = createEffect(tr("低音增强"), { BassBoost(0, audioSessionId) }) {
            check(it.strengthSupported)
            check(it.setEnabled(false) == AudioEffect.SUCCESS)
        }
        virtualizer = createEffect(tr("3D 环绕"), { Virtualizer(0, audioSessionId) }) {
            check(it.strengthSupported)
            check(it.setEnabled(false) == AudioEffect.SUCCESS)
        }
        loudness = createEffect(tr("响度增强"), { LoudnessEnhancer(audioSessionId) }) {
            check(it.setEnabled(false) == AudioEffect.SUCCESS)
        }
        // PresetReverb 是辅助效果；session 0 创建，由 AudioTrack 的 aux send 接入。
        reverb = createEffect(tr("混响"), { PresetReverb(0, 0) }) {
            it.preset = PresetReverb.PRESET_MEDIUMHALL
            check(it.setEnabled(false) == AudioEffect.SUCCESS)
        }
        publish()
        return capabilities.any
    }

    fun applySettings(settings: AudioEffectSettings) {
        val safe = settings.normalized()
        equalizer = applyEffect(tr("均衡器"), equalizer) { eq ->
            check(eq.setEnabled(true) == AudioEffect.SUCCESS)
            for (band in 0 until eq.numberOfBands.toInt()) {
                val gainDb = interpolateEqGain(eq.getCenterFreq(band.toShort()) / 1000f, safe.eqBands)
                eq.setBandLevel(band.toShort(), (gainDb * 100f).toInt().coerceIn(
                    eq.bandLevelRange[0].toInt(), eq.bandLevelRange[1].toInt()
                ).toShort())
            }
        }
        bassBoost = applyEffect(tr("低音增强"), bassBoost) {
            it.setStrength((safe.bassBoost * 10).toShort())
            check(it.setEnabled(safe.bassBoost > 0) == AudioEffect.SUCCESS)
        }
        virtualizer = applyEffect(tr("3D 环绕"), virtualizer) {
            it.setStrength((safe.virtualizer * 10).toShort())
            check(it.setEnabled(safe.virtualizer > 0) == AudioEffect.SUCCESS)
        }
        loudness = applyEffect(tr("响度增强"), loudness) {
            it.setTargetGain(safe.loudnessGain * 6)
            check(it.setEnabled(safe.loudnessGain > 0) == AudioEffect.SUCCESS)
        }
        reverb = applyEffect(tr("混响"), reverb) {
            check(it.setEnabled(safe.reverbWet > 0) == AudioEffect.SUCCESS)
        }
        reverbSendLevel = if (reverb != null) safe.reverbWet / 100f else 0f
        publish()
    }

    fun disableReverb() {
        runCatching { reverb?.release() }
        reverb = null
        reverbSendLevel = 0f
        publish()
    }

    fun release() = release(publish = true)

    private fun release(publish: Boolean) {
        listOf(equalizer, bassBoost, virtualizer, loudness, reverb).forEach { runCatching { it?.release() } }
        equalizer = null
        bassBoost = null
        virtualizer = null
        loudness = null
        reverb = null
        reverbSendLevel = 0f
        capabilities = SystemEffectCapabilities()
        if (publish) AudioEffectStatus.publishSystem(capabilities, false)
    }

    private fun publish() {
        capabilities = SystemEffectCapabilities(
            equalizer = equalizer != null, bassBoost = bassBoost != null,
            virtualizer = virtualizer != null, loudness = loudness != null, reverb = reverb != null
        )
        AudioEffectStatus.publishSystem(capabilities, true)
    }

    private inline fun <T : AudioEffect> createEffect(name: String, create: () -> T, setup: (T) -> Unit): T? {
        var effect: T? = null
        return try {
            create().also { effect = it; check(it.hasControl()); setup(it) }
        } catch (error: Exception) {
            runCatching { effect?.release() }
            Log.w(TAG, "$name 不可用", error)
            null
        }
    }

    private inline fun <T : AudioEffect> applyEffect(name: String, effect: T?, block: (T) -> Unit): T? {
        effect ?: return null
        return try {
            check(effect.hasControl())
            block(effect)
            effect
        } catch (error: Exception) {
            runCatching { effect.release() }
            Log.w(TAG, "应用${name}失败", error)
            null
        }
    }

    companion object {
        private const val TAG = "SystemAudioFX"

        internal fun interpolateEqGain(frequency: Float, gains: List<Float>): Float {
            val frequencies = EQPresets.frequencies
            if (frequency <= frequencies.first()) return gains.firstOrNull() ?: 0f
            if (frequency >= frequencies.last()) return gains.getOrNull(9) ?: 0f
            val upper = frequencies.indexOfFirst { it >= frequency }
            if (upper <= 0) return 0f
            val lower = upper - 1
            val position = (ln(frequency) - ln(frequencies[lower].toFloat())) /
                (ln(frequencies[upper].toFloat()) - ln(frequencies[lower].toFloat()))
            val lowGain = gains.getOrNull(lower) ?: 0f
            val highGain = gains.getOrNull(upper) ?: 0f
            return lowGain + (highGain - lowGain) * position
        }
    }
}
