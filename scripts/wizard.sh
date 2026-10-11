#!/bin/sh
# UU Remote WOL Router Helper / interactive front-end.
# Front-end only: backend guards, checks, and rollback contracts remain intact.
ROOT_DIR=$(CDPATH= cd "$(dirname "$0")/.." 2>/dev/null && pwd) || exit 1
. "$ROOT_DIR/lib/channel.sh"
. "$ROOT_DIR/lib/wizard-policy.sh"

WIZARD_PREVIEW=no
[ "${1:-}" = "--preview" ] && WIZARD_PREVIEW=yes
if [ "$WIZARD_PREVIEW" != yes ] && [ ! -t 0 ]; then
    printf '%s\n' '交互向导需要 SSH 交互终端。请直接运行 sh uu-helper.sh start。' >&2
    exit 64
fi

# No ANSI output in redirected/logged sessions, narrow dumb terminals,
# or when the conventional NO_COLOR setting is present.
c_reset='' c_accent='' c_green='' c_yellow='' c_dim='' c_bold=''
if [ -t 1 ] && [ -z "${NO_COLOR+x}" ] && [ "${TERM:-dumb}" != dumb ]; then
    c_reset=$(printf '\033[0m')
    c_accent=$(printf '\033[1;36m')
    c_green=$(printf '\033[1;32m')
    c_yellow=$(printf '\033[1;33m')
    c_dim=$(printf '\033[2m')
    c_bold=$(printf '\033[1m')
fi

wizard_columns="${COLUMNS:-}"
case "$wizard_columns" in ''|*[!0-9]*) wizard_columns=80 ;; esac
if [ -t 1 ] && command -v stty >/dev/null 2>&1; then
    terminal_size=$(stty size 2>/dev/null || true)
    if [ -n "$terminal_size" ]; then
        terminal_cols=${terminal_size##* }
        case "$terminal_cols" in ''|*[!0-9]*) ;; *) wizard_columns=$terminal_cols ;; esac
    fi
fi
divider() {
    if [ "$wizard_columns" -lt 55 ]; then
        printf '%s\n' '  ───────────────────────────'
    else
        printf '%s\n' '  ──────────────────────────────────────────'
    fi
}
heading() {
    printf '\n%s  %s%s%s\n' "$c_accent" "$1" "$c_reset" ''
}
pause_menu() {
    printf '\n%s按回车返回菜单：%s' "$c_dim" "$c_reset"
    IFS= read -r _unused || return 1
}
confirm_word() {
    expected="$1"
    printf '\n%s输入 %s 确认；直接回车取消：%s' "$c_yellow" "$expected" "$c_reset"
    IFS= read -r reply || return 1
    [ "$reply" = "$expected" ]
}
status_text() {
    case "$1" in
        official) printf '%s优先使用网易官方方案%s' "$c_green" "$c_reset" ;;
        experimental) printf '%s测试中 · 暂不支持正式安装%s' "$c_yellow" "$c_reset" ;;
        migration) printf '%s仅限已有官方插件的设备%s' "$c_yellow" "$c_reset" ;;
        candidate) printf '%s可尝试测试 · 尚未保证型号兼容%s' "$c_yellow" "$c_reset" ;;
        *) printf '%s尚不支持安装 · 可查看诊断信息%s' "$c_yellow" "$c_reset" ;;
    esac
}
detect_device() {
    device_platform=unknown
    device_arch=unknown
    device_model='未识别'
    device_health='未检查'
    detected=''
    if sh "$ROOT_DIR/platforms/xiaoqiang/detect.sh" >/dev/null 2>&1; then
        device_platform=xiaoqiang
        detected=$(sh "$ROOT_DIR/platforms/xiaoqiang/detect.sh" 2>/dev/null)
    elif sh "$ROOT_DIR/platforms/asuswrt/detect.sh" >/dev/null 2>&1; then
        device_platform=asuswrt
        detected=$(sh "$ROOT_DIR/platforms/asuswrt/detect.sh" 2>/dev/null)
    elif sh "$ROOT_DIR/platforms/openwrt/detect.sh" >/dev/null 2>&1; then
        device_platform=openwrt
        detected=$(sh "$ROOT_DIR/platforms/openwrt/detect.sh" 2>/dev/null)
    fi
    if [ "$device_platform" != unknown ]; then
        device_model=$(printf '%s\n' "$detected" | sed -n 's/^model: //p' | head -n 1)
        [ -n "$device_model" ] || device_model='未提供型号'
    fi
    if [ "$device_platform" = openwrt ]; then
        device_arch=$(uu_openwrt_detect_arch 2>/dev/null || printf unknown)
    elif [ "$device_platform" != unknown ]; then
        device_arch=$(uname -m 2>/dev/null || printf unknown)
    fi
    wizard_mode=$(uu_wizard_mode "$device_platform" "$device_arch")
    if [ "$device_platform" != unknown ]; then
        if sh "$ROOT_DIR/platforms/$device_platform/health.sh" >/dev/null 2>&1; then
            device_health='核心服务已检测到'
        else
            device_health='未确认核心服务完整在线'
        fi
    fi
}
show_header() {
    printf '\n%s' "$c_accent"
    if [ "$wizard_columns" -lt 55 ]; then
        printf '%s\n' '  ╭──────────────────────────'
        printf '%s\n' '  │  UU 远程开机助手'
        printf '%s\n' '  │  自动识别 · 安全操作'
        printf '%s\n' '  ╰──────────────────────────'
    else
        printf '%s\n' '  ╭──────────────────────────────────────────'
        printf '%s\n' '  │  UU REMOTE  ·  远程开机路由器助手'
        printf '%s\n' '  │  简单操作 · 自动识别 · 安全可回退'
        printf '%s\n' '  ╰──────────────────────────────────────────'
    fi
    printf '%s' "$c_reset"
    printf '\n  %s设备%s  %s\n' "$c_bold" "$c_reset" "$device_model"
    printf '  %s系统%s  %s  ·  %s\n' "$c_bold" "$c_reset" "$device_platform" "$device_arch"
    printf '  %s状态%s  ' "$c_bold" "$c_reset"
    status_text "$wizard_mode"
    printf '\n  %s服务%s  %s\n' "$c_bold" "$c_reset" "$device_health"
}
show_menu() {
    show_header
    divider
    printf '  %s1%s  查看设备状态\n' "$c_accent" "$c_reset"
    if uu_wizard_can_stage "$wizard_mode"; then
        printf '  %s2%s  下载并检查插件\n' "$c_accent" "$c_reset"
    fi
    if uu_wizard_can_setup "$wizard_mode"; then
        printf '  %s3%s  测试并安装（需确认）\n' "$c_accent" "$c_reset"
    fi
    printf '  %s4%s  手机绑定与远程开机说明\n' "$c_accent" "$c_reset"
    printf '  %s5%s  生成问题报告（自动隐去敏感信息）\n' "$c_accent" "$c_reset"
    if uu_wizard_can_rollback "$wizard_mode"; then
        printf '  %s6%s  恢复之前的配置（需要备份）\n' "$c_accent" "$c_reset"
    fi
    divider
    printf '  %s0%s  退出\n\n' "$c_dim" "$c_reset"
    case "$wizard_mode" in
        experimental) printf '  %s该型号远程唤醒尚未通过测试，不能正式安装。%s\n' "$c_yellow" "$c_reset" ;;
        official) printf '  %s请优先使用路由器厂商和网易官方的集成入口。%s\n' "$c_green" "$c_reset" ;;
        collect) printf '  %s尚未识别为支持的设备，不能下载或安装插件。%s\n' "$c_yellow" "$c_reset" ;;
    esac
}

show_bind_help() {
    heading '手机绑定与最终验收'
    printf '%s\n' '  1  Windows UU远程：配置网卡 / BIOS 的 WOL（局域网唤醒）。'
    printf '%s\n' '  2  手机连接家中 Wi-Fi，进入网易 UU 主机加速器。'
    printf '%s\n' '     路由器加速 → 合作款路由器 → 添加 / 绑定。'
    printf '%s\n' '  3  确保主机加速器与 Windows UU远程账号对应正确。'
    printf '%s\n' '  4  Windows UU远程中刷新辅助设备，逐台配置电脑。'
    printf '%s\n' '  5  手机关闭 Wi-Fi，只用移动数据尝试唤醒关机电脑。'
    printf '\n  %s只有真实移动数据远程开机成功才算功能通过。%s\n' "$c_yellow" "$c_reset"
}
prepare_stage() {
    if ! uu_wizard_can_stage "$wizard_mode"; then
        printf '此设备不开放官方下载准备。\n'
        return 2
    fi
    heading '下载并检查网易官方插件'
    printf '%s\n' '  将自动检查设备、选择适用版本并校验下载文件。'
    printf '%s\n' '  只写入 /tmp 临时目录，不会启动插件或安装开机自启。'
    confirm_word DOWNLOAD || { printf '  已取消。\n'; return 0; }
    if ! sh "$ROOT_DIR/uu-helper.sh" preflight; then
        printf '\n  %s设备预检未通过，已停止。%s\n' "$c_yellow" "$c_reset"
        return 1
    fi
    if ! sh "$ROOT_DIR/uu-helper.sh" stage auto; then
        printf '\n  %s官方下载或校验失败，已停止。%s\n' "$c_yellow" "$c_reset"
        return 1
    fi
    printf '\n  %s下载和检查已完成，插件尚未运行或安装。%s\n' "$c_green" "$c_reset"
    return 0
}
guided_setup() {
    if ! uu_wizard_can_setup "$wizard_mode"; then
        printf '%s\n' '  此设备还不能使用安装功能，操作已停止。'
        return 2
    fi
    heading '测试并安装 · 请先了解风险'
    printf '%s\n' '  本操作可能改变路由器运行状态，不是无风险的一键安装。'
    printf '%s\n' '  临时测试可能修改防火墙或短暂影响网络。'
    printf '%s\n' '  只在已备份配置、能本地恢复路由器网络时执行。'
    printf '%s\n' '  检测到适用处理器，也不代表当前路由器型号已通过测试。'
    confirm_word TEST || { printf '  已取消。\n'; return 0; }

    if ! sh "$ROOT_DIR/uu-helper.sh" preflight ||
       ! sh "$ROOT_DIR/uu-helper.sh" stage auto; then
        printf '\n  %s预检或官方插件准备失败，已停止后续操作。%s\n' "$c_yellow" "$c_reset"
        return 1
    fi
    printf '\n  %s接下来仅临时启动插件，期间可用手机移动数据尝试远程开机。%s\n' "$c_yellow" "$c_reset"
    confirm_word RUN || { printf '  已取消临时启动，插件只保留在 /tmp。\n'; return 0; }
    case "$wizard_mode" in
        candidate)
            UU_RUNTIME_TEST_CONFIRM=TEMPORARY_RUNTIME_CHANGE sh "$ROOT_DIR/platforms/openwrt/smoke-test.sh" || return 1
            ;;
        migration)
            UU_RUNTIME_TEST_CONFIRM=TEMPORARY_RUNTIME_CHANGE sh "$ROOT_DIR/platforms/xiaoqiang/smoke-test.sh" || return 1
            ;;
        *) return 2 ;;
    esac

    printf '\n%s' "$c_yellow"
    printf '%s\n' '  临时运行检查通过 ≠ 手机远程唤醒通过。'
    printf '%s' "$c_reset"
    printf '%s\n' '  只有在测试窗口内，使用移动数据确实唤醒目标电脑，'
    printf '%s\n' '  且愿意进行持久安装时，才继续。'
    confirm_word WOL_OK || { printf '%s\n' '  未确认远程唤醒成功，不执行正式安装。'; return 0; }

    printf '\n%s\n' '  即将写入持久文件和启动服务；失败由底层安装脚本尝试回滚。'
    printf '%s\n' '  请确认有现场恢复能力，避免覆盖现有官方插件。'
    confirm_word INSTALL || { printf '%s\n' '  已取消持久安装。'; return 0; }
    if [ "$wizard_mode" = candidate ]; then
        UU_PERSIST_INSTALL_CONFIRM=PERSIST_OPENWRT_UU sh "$ROOT_DIR/platforms/openwrt/install.sh" || return 1
    else
        UU_XQ_INSTALL_CONFIRM=MIGRATE_XIAOQIANG_UU sh "$ROOT_DIR/platforms/xiaoqiang/install.sh" || return 1
    fi
    printf '\n  %s安装流程返回成功；请重启验收，并按菜单 4 验证真实手机唤醒。%s\n' "$c_green" "$c_reset"
}
restore_previous() {
    if ! uu_wizard_can_rollback "$wizard_mode"; then
        printf '%s\n' '  本设备不可使用该回滚路径。'
        return 2
    fi
    heading '恢复之前的配置'
    printf '%s\n' '  尝试恢复本工具保存的上一次安装前配置。'
    printf '%s\n' '  没有有效备份时将停止，不会猜测或覆盖配置。'
    confirm_word ROLLBACK || { printf '%s\n' '  已取消。'; return 0; }
    case "$wizard_mode" in
        candidate) UU_ROLLBACK_CONFIRM=ROLLBACK_OPENWRT_UU sh "$ROOT_DIR/platforms/openwrt/rollback.sh" ;;
        migration) UU_XQ_ROLLBACK_CONFIRM=ROLLBACK_XIAOQIANG_UU sh "$ROOT_DIR/platforms/xiaoqiang/rollback.sh" ;;
    esac
}
run_menu() {
    detect_device
    if [ "$WIZARD_PREVIEW" = yes ]; then
        show_menu
        return 0
    fi
    while :; do
        show_menu
        printf '  %s请选择序号 › %s' "$c_accent" "$c_reset"
        IFS= read -r selected || { printf '\n'; return 0; }
        case "$selected" in
            0|q|Q) printf '\n  已安全退出。\n'; return 0 ;;
            1) heading '只读设备诊断'; sh "$ROOT_DIR/uu-helper.sh" diagnose; detect_device ;;
            2) if uu_wizard_can_stage "$wizard_mode"; then prepare_stage; else printf '  无此选项。\n'; fi ;;
            3) if uu_wizard_can_setup "$wizard_mode"; then guided_setup; else printf '  此设备不允许安装。\n'; fi ;;
            4) show_bind_help ;;
            5) heading '问题报告（自动隐去敏感信息）'; sh "$ROOT_DIR/uu-helper.sh" collect-info ;;
            6) if uu_wizard_can_rollback "$wizard_mode"; then restore_previous; else printf '  此设备不能使用本项目回滚。\n'; fi ;;
            *) printf '%s\n' '  请输入菜单中的数字，或输入 0 退出。' ;;
        esac
        pause_menu || return 0
    done
}
run_menu
