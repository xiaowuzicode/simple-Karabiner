#!/bin/bash
# DJI Mic Mini 三段式语音听写 — Whisper 流式版
#
# 与原版 dictation-enter.sh 的区别：
#   - 不依赖 闪电说 / right_command，改用本地 whisper.cpp stream
#   - confirm 动作自动把识别文字粘贴到当前 App，再发 Enter
#   - 其余三段式状态机逻辑与原版完全相同
#
# 依赖: whisper-stream.sh (同目录), brew install whisper-cpp

STATE_DIR="${STATE_DIR:-/tmp/dji-dictation}"
LOG="${LOG:-$STATE_DIR/debug.log}"
KCLI="${KCLI:-/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli}"
CONFIRM_WINDOW="${CONFIRM_WINDOW:-5}"
OSASCRIPT_BIN="${OSASCRIPT_BIN:-/usr/bin/osascript}"
AFPLAY_BIN="${AFPLAY_BIN:-/usr/bin/afplay}"
TMUX_BIN="${TMUX_BIN:-$(command -v tmux 2>/dev/null || echo /opt/homebrew/bin/tmux)}"
WHISPER_STREAM="${WHISPER_STREAM:-$HOME/.config/karabiner/scripts/whisper-stream.sh}"

/bin/mkdir -p "$STATE_DIR"

timestamp() { /bin/date +%H:%M:%S; }
log() { /usr/bin/printf '%s %s\n' "$(timestamp)" "$*" >> "$LOG"; }
read_file() { /bin/cat "$STATE_DIR/$1" 2>/dev/null; }
write_file() { /usr/bin/printf '%s' "$2" > "$STATE_DIR/$1"; }
set_vars() { "$KCLI" --set-variables "$1" 2>/dev/null; }

play_sound() {
    local name="$1"
    [ -n "$name" ] || return 0
    if [ -f "/System/Library/Sounds/${name}.aiff" ]; then
        "$AFPLAY_BIN" -v 0.3 "/System/Library/Sounds/${name}.aiff" &
    fi
}

active_tmux_pane() {
    "$TMUX_BIN" list-panes -a \
        -F '#{session_attached} #{window_active} #{pane_active} #{pane_id}' 2>/dev/null |
        awk '$1==1 && $2==1 && $3==1 {print $4; exit}'
}

gui_send_enter() {
    local bundle
    bundle="$("$OSASCRIPT_BIN" -e \
        'tell application "System Events"
            set bid to bundle identifier of first application process whose frontmost is true
            if bid is not "com.googlecode.iterm2" then keystroke return
            return bid
        end tell' 2>/dev/null)"
    if [ "$bundle" = "com.googlecode.iterm2" ]; then
        "$OSASCRIPT_BIN" -e \
            'tell application "iTerm2" to tell current window to tell current session to write text ""' 2>/dev/null
    fi
    log "gui_send_enter bundle=$bundle"
}

send_enter() {
    local source="$1"
    local mode pane
    mode="$(read_file mode)"
    if [ "$mode" = "tmux" ]; then
        pane="$(read_file pane_id)"
        if [ -n "$pane" ]; then
            "$TMUX_BIN" send-keys -t "$pane" Enter 2>/dev/null
            log "$source tmux send_enter pane=$pane"
            return 0
        fi
    fi
    gui_send_enter
}

# 粘贴识别文字到当前焦点 App
paste_text() {
    local text="$1"
    [ -n "$text" ] || return 0

    local mode pane
    mode="$(read_file mode)"
    pane="$(read_file pane_id)"

    if [ "$mode" = "tmux" ] && [ -n "$pane" ]; then
        # tmux 模式：直接发送文字到 pane（不经过剪贴板）
        "$TMUX_BIN" send-keys -t "$pane" "$text" 2>/dev/null
        log "paste_text tmux pane=$pane text='$text'"
    else
        # GUI 模式：写入剪贴板再 Cmd+V 粘贴（兼容中文）
        /usr/bin/printf '%s' "$text" | /usr/bin/pbcopy
        "$OSASCRIPT_BIN" -e \
            'tell application "System Events" to keystroke "v" using {command down}' 2>/dev/null
        log "paste_text gui clipboard text='$text'"
    fi
}

kill_old_watcher() {
    local pid
    pid="$(read_file watcher.pid)"
    if [ -n "$pid" ] && /bin/kill -0 "$pid" 2>/dev/null; then
        /bin/kill "$pid" 2>/dev/null
        /bin/kill -9 "$pid" 2>/dev/null
    fi
    /bin/rm -f "$STATE_DIR/watcher.pid"
}

cleanup() {
    /bin/rm -f "$STATE_DIR"/{mode,pane_id,watcher.pid,session_id}
}

# Route handling: dictation-whisper.sh route <branch> <action>
if [ "$1" = "route" ]; then
    branch="$2"
    action="$3"
    shift 3
    log "branch_hit $branch"
    set -- "$action" "$@"
fi

case "$1" in
save)
    kill_old_watcher
    set_vars '{"dji_ready_to_send":0,"dji_watching":0}'
    cleanup

    # 检测当前前台 App，判断是 tmux 还是 GUI 模式（逻辑与原版相同）
    front_bundle="$("$OSASCRIPT_BIN" -e \
        'tell application "System Events" to return bundle identifier of first application process whose frontmost is true' 2>/dev/null)"

    pane=""
    case "$front_bundle" in
    com.googlecode.iterm2)
        iterm_win="$("$OSASCRIPT_BIN" -e 'tell app "iTerm" to name of current window' 2>/dev/null)"
        case "$iterm_win" in "↣"*) pane="$(active_tmux_pane)" ;; esac
        ;;
    net.kovidgoyal.kitty | io.alacritty | com.apple.Terminal)
        pane="$(active_tmux_pane)"
        ;;
    esac

    if [ -n "$pane" ]; then
        write_file mode tmux
        write_file pane_id "$pane"
        log "save mode=tmux pane=$pane app=$front_bundle"
    else
        write_file mode gui
        log "save mode=gui app=$front_bundle"
    fi
    write_file session_id "$$-$(/bin/date +%s)"

    # 启动 Whisper 流式识别
    if [ -x "$WHISPER_STREAM" ]; then
        "$WHISPER_STREAM" start
    else
        log "ERROR: whisper-stream.sh not found at $WHISPER_STREAM"
    fi
    ;;

watch)
    kill_old_watcher
    write_file watcher.pid "$$"

    # 停止 Whisper 识别，同时触发通知展示识别文字
    if [ -x "$WHISPER_STREAM" ]; then
        "$WHISPER_STREAM" stop
    fi

    play_sound Tink
    set_vars '{"dji_watching":0,"dji_ready_to_send":1}'
    log "watch ready confirm_window=${CONFIRM_WINDOW}s"

    # 等待确认（超时则静默重置）
    /bin/sleep "$CONFIRM_WINDOW"

    set_vars '{"dji_ready_to_send":0}'
    log "watch timeout_reset"
    /bin/rm -f "$STATE_DIR/watcher.pid"
    cleanup
    ;;

preconfirm)
    # 检查在确认窗口内快速按下的情况，逻辑同 confirm
    text=""
    if [ -x "$WHISPER_STREAM" ]; then
        text="$("$WHISPER_STREAM" get-text)"
    fi
    paste_text "$text"
    play_sound Tink
    send_enter preconfirm
    kill_old_watcher
    set_vars '{"dji_watching":0,"dji_ready_to_send":0}'
    cleanup
    log "preconfirm done text='$text'"
    ;;

confirm)
    text=""
    if [ -x "$WHISPER_STREAM" ]; then
        text="$("$WHISPER_STREAM" get-text)"
    fi
    paste_text "$text"
    play_sound Tink
    send_enter confirm
    kill_old_watcher
    set_vars '{"dji_watching":0,"dji_ready_to_send":0}'
    cleanup
    log "confirm done text='$text'"
    ;;

*)
    log "unknown action: $1"
    ;;
esac
