#!/bin/bash
# whisper-stream.sh — real-time Whisper transcription backend for DJI Mic Mini
#
# Setup:
#   brew install whisper-cpp
#   whisper-cpp-download-ggml-model large-v3   # 3GB, M4 Pro 推荐
#   # OR: whisper-cpp-download-ggml-model medium  # 1.5GB, 更快
#
# 麦克风权限: 系统设置 → 隐私与安全 → 麦克风 → 授权终端 App (iTerm2 / Terminal)
#
# Usage (called by dictation-whisper.sh):
#   whisper-stream.sh start          — 开始流式识别
#   whisper-stream.sh stop           — 停止录音，写入最终文字
#   whisper-stream.sh get-text       — 输出最终文字到 stdout
#   whisper-stream.sh status         — 输出 recording / idle
#   whisper-stream.sh install-check  — 检查依赖

STATE_DIR="${STATE_DIR:-/tmp/dji-dictation}"
LOG="${STATE_DIR}/debug.log"
RAW_FILE="${STATE_DIR}/whisper-raw.txt"
TRANSCRIPT_FILE="${STATE_DIR}/whisper-transcript.txt"
PID_FILE="${STATE_DIR}/whisper-stream.pid"
AFPLAY_BIN="${AFPLAY_BIN:-/usr/bin/afplay}"

# 可通过环境变量覆盖
WHISPER_LANG="${WHISPER_LANG:-zh}"
WHISPER_STEP="${WHISPER_STEP:-800}"       # ms: 每次刷新间隔，越小越实时
WHISPER_LENGTH="${WHISPER_LENGTH:-30000}" # ms: 滑动窗口长度，覆盖约 30s 录音
WHISPER_THREADS="${WHISPER_THREADS:-6}"   # M4 Pro 有 12 核，6 线程留余量

/bin/mkdir -p "$STATE_DIR"
timestamp() { /bin/date +%H:%M:%S; }
log() { /usr/bin/printf '%s whisper-stream: %s\n' "$(timestamp)" "$*" >> "$LOG"; }
notify() { /usr/bin/osascript -e "display notification \"$*\" with title \"🎤 Whisper\"" 2>/dev/null & }

find_stream_bin() {
    # whisper-cpp 1.7+ 改名为 whisper-stream
    for p in \
        /opt/homebrew/bin/whisper-stream \
        /usr/local/bin/whisper-stream \
        /opt/homebrew/bin/stream \
        /usr/local/bin/stream \
        "${HOME}/.local/bin/whisper-stream"; do
        [ -x "$p" ] && echo "$p" && return 0
    done
    return 1
}

find_model() {
    # 按质量从高到低，检查常见位置
    for dir in "${HOME}/.cache/whisper" /tmp /opt/homebrew/share/whisper-cpp; do
        for name in \
            ggml-large-v3.bin \
            ggml-large-v2.bin \
            ggml-medium.bin \
            ggml-small.bin \
            ggml-base.bin; do
            local path="${dir}/${name}"
            [ -f "$path" ] && echo "$path" && return 0
        done
    done
    return 1
}

kill_stream() {
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(/bin/cat "$PID_FILE" 2>/dev/null)
        if [ -n "$pid" ]; then
            /bin/kill "$pid" 2>/dev/null
            /bin/sleep 0.3
            /bin/kill -9 "$pid" 2>/dev/null
            log "killed stream pid=$pid"
        fi
        /bin/rm -f "$PID_FILE"
    fi
}

get_final_text() {
    # -f 输出的是纯文本（每步追加一行），取最后一行
    /usr/bin/grep -v '^\s*$' "$RAW_FILE" 2>/dev/null \
        | /usr/bin/tail -1 \
        | /usr/bin/sed 's/^[[:space:]]*//' \
        | /usr/bin/sed 's/[[:space:]]*$//'
}

case "$1" in
start)
    kill_stream
    > "$RAW_FILE"
    > "$TRANSCRIPT_FILE"

    STREAM_BIN="${WHISPER_STREAM_BIN:-$(find_stream_bin)}"
    MODEL="${WHISPER_MODEL:-$(find_model)}"

    if [ -z "$STREAM_BIN" ]; then
        notify "❌ 未找到 stream，请 brew install whisper-cpp"
        log "ERROR: stream binary not found"
        exit 1
    fi
    if [ -z "$MODEL" ]; then
        notify "❌ 未找到模型，请运行: whisper-cpp-download-ggml-model large-v3"
        log "ERROR: no whisper model found"
        exit 1
    fi

    log "start bin=$STREAM_BIN model=$(basename "$MODEL") lang=$WHISPER_LANG"
    notify "🎤 开始录音..."

    # 用 -f 把识别文字写入文件（干净文本，无 ANSI 转义码）
    "$STREAM_BIN" \
        -m "$MODEL" \
        -l "$WHISPER_LANG" \
        --step "$WHISPER_STEP" \
        --length "$WHISPER_LENGTH" \
        --keep 500 \
        -f "$RAW_FILE" \
        2>/dev/null &

    echo $! > "$PID_FILE"
    log "stream started pid=$!"
    ;;

stop)
    kill_stream

    text=$(get_final_text)
    log "stop final_text='$text'"

    if [ -n "$text" ]; then
        /usr/bin/printf '%s' "$text" > "$TRANSCRIPT_FILE"
        notify "✅ 识别完成：${text}"
    else
        notify "⚠️ 未识别到文字"
        > "$TRANSCRIPT_FILE"
    fi
    ;;

get-text)
    /bin/cat "$TRANSCRIPT_FILE" 2>/dev/null
    ;;

status)
    if [ -f "$PID_FILE" ] && /bin/kill -0 "$(/bin/cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; then
        echo "recording"
    else
        echo "idle"
    fi
    ;;

install-check)
    /usr/bin/printf '=== Whisper Stream 依赖检查 ===\n\n'

    STREAM_BIN=$(find_stream_bin)
    if [ -n "$STREAM_BIN" ]; then
        /usr/bin/printf '✅ stream 二进制: %s\n' "$STREAM_BIN"
    else
        /usr/bin/printf '❌ stream 二进制: 未找到\n'
        /usr/bin/printf '   修复: brew install whisper-cpp\n\n'
    fi

    MODEL=$(find_model)
    if [ -n "$MODEL" ]; then
        /usr/bin/printf '✅ 模型: %s\n' "$MODEL"
    else
        /usr/bin/printf '❌ 模型: 未找到\n'
        /usr/bin/printf '   修复: whisper-cpp-download-ggml-model large-v3\n'
        /usr/bin/printf '   (M4 Pro 运行 large-v3 延迟约 500ms，推荐)\n\n'
    fi

    /usr/bin/printf '\n系统权限:\n'
    /usr/bin/printf '  系统设置 → 隐私与安全 → 麦克风 → 授权终端 App\n'
    /usr/bin/printf '\n===================================\n'
    ;;

*)
    /usr/bin/printf 'Usage: %s {start|stop|get-text|status|install-check}\n' "$0"
    exit 1
    ;;
esac
