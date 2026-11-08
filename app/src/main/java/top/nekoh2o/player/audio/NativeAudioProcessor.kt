package top.nekoh2o.player.audio

import top.nekoh2o.player.i18n.NekoI18n.tr

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.util.UnstableApi
import kotlinx.coroutines.flow.update
import top.nekoh2o.player.data.model.AudioEffectEngine
import top.nekoh2o.player.data.model.AudioEffectSettings
import java.nio.ByteBuffer

/**
 * 常驻 PCM 管线：关闭/系统引擎时原样传递，切换时不重建播放器。
 * BaseAudioProcessor 管理输出交接和 EOS；JNI 状态只由播放线程访问。
 */
@UnstableApi
class NativeAudioProcessor internal constructor(
    private val backend: NativeEffectBackend,
    private val reportError: (String?) -> Unit
) : BaseAudioProcessor() {
    constructor() : this(JniEffectBackend(), { error ->
        AudioEffectStatus.state.update { it.copy(nativeError = error) }
    })

    @Volatile private var settings = AudioEffectSettings()
    private var appliedSettings: AudioEffectSettings? = null
    private var handle = 0L
    private var failed = false
    private var failedSettings: AudioEffectSettings? = null
    private var wasNative = false

    fun applySettings(settings: AudioEffectSettings) {
        this.settings = settings.normalized()
    }

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        // DefaultAudioSink 负责将其他整数 PCM 格式转换为 PCM16。
        return if (inputAudioFormat.encoding == C.ENCODING_PCM_16BIT) inputAudioFormat
        else AudioProcessor.AudioFormat.NOT_SET
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        if (!inputBuffer.hasRemaining() || hasPendingOutput()) return
        val current = settings
        val native = current.engine == AudioEffectEngine.NATIVE_CPP
        val original = inputBuffer.duplicate()
        val output = replaceOutputBuffer(inputBuffer.remaining())
        // put 推进输入和输出位置；ShortBuffer 视图不会推进 ByteBuffer。
        output.put(inputBuffer).flip()
        if (!native) {
            if (wasNative) releaseEngine()
            wasNative = false
            failed = false
            reportError(null)
            return
        }
        wasNative = true
        val channels = inputAudioFormat.channelCount
        if (channels !in 1..2 || output.remaining() % (channels * 2) != 0) {
            reportError(tr("专业音效仅支持完整的单/双声道 PCM 帧；当前音频已原样播放"))
            return
        }
        if (failed && failedSettings == current) return
        failed = false
        try {
            if (handle == 0L) {
                handle = backend.create(inputAudioFormat.sampleRate, channels)
                check(handle != 0L) { tr("DSP 初始化失败") }
            }
            if (appliedSettings != current) {
                backend.configure(handle, current)
                appliedSettings = current
            }
            backend.process(handle, output, output.remaining() / 2)
            reportError(null)
        } catch (error: LinkageError) {
            bypassAfterFailure(output, original, error, current)
        } catch (error: Exception) {
            bypassAfterFailure(output, original, error, current)
        }
    }

    private fun bypassAfterFailure(
        output: ByteBuffer, original: ByteBuffer, error: Throwable, attempted: AudioEffectSettings
    ) {
        output.clear()
        output.put(original).flip()
        failed = true
        failedSettings = attempted
        reportError(tr("专业音效不可用，已原样播放：{reason}", "reason" to (error.message ?: error.javaClass.simpleName)))
        releaseEngine()
    }

    override fun onFlush() {
        // seek/换曲清除延迟线，configure 的新格式在 flush 后才生效。
        releaseEngine()
        failed = false
        wasNative = false
    }

    override fun onReset() {
        releaseEngine()
        reportError(null)
    }

    private fun releaseEngine() {
        val oldHandle = handle
        handle = 0L
        appliedSettings = null
        if (oldHandle != 0L) {
            try { backend.release(oldHandle) } catch (_: LinkageError) {
            } catch (_: Exception) { }
        }
    }
}
