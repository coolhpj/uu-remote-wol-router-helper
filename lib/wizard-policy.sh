#!/bin/sh
# Public interactive menu policy. Device architecture is a safety boundary:
# a matching CPU is NOT proof that a router model supports remote WOL.
uu_wizard_mode() {
    case "$1:$2" in
        asuswrt:*) printf 'official\n' ;;
        openwrt:mipsel_24kc) printf 'experimental\n' ;;
        openwrt:x86_64|openwrt:aarch64|openwrt:arm64) printf 'candidate\n' ;;
        xiaoqiang:aarch64|xiaoqiang:arm64) printf 'migration\n' ;;
        *) printf 'collect\n' ;;
    esac
}
uu_wizard_can_stage() {
    case "$1" in candidate|migration|experimental) return 0 ;; *) return 1 ;; esac
}
uu_wizard_can_setup() {
    case "$1" in candidate|migration) return 0 ;; *) return 1 ;; esac
}
uu_wizard_can_rollback() {
    uu_wizard_can_setup "$1"
}
