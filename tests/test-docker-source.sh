#!/bin/sh
set -eu
sh -n docker/entrypoint.sh
sh -n scripts/stage-package.sh
bash -n tests/docker-real-identity-persistence.sh
bash -n tests/docker-compose-lifecycle.sh
grep -q 'UU_COMPOSE_DOWN_PRESERVES_IDENTITY_VOLUME=pass' tests/docker-compose-lifecycle.sh
grep -q 'UU_REAL_IDENTITY_AFTER_REFRESH=preserved' tests/docker-real-identity-persistence.sh
grep -q 'UU_REAL_IDENTITY_AFTER_RECREATE=preserved' tests/docker-real-identity-persistence.sh
grep -q '^## Docker 容器安装（实验版）' README.md
grep -q 'git clone --branch feat/docker-experimental --single-branch' README.md
grep -q 'docker compose down' docker/README.md
grep -q 'scripts/stage-package.sh' docker/entrypoint.sh
grep -q 'uu_resolve_channel' docker/entrypoint.sh
grep -q 'NET_RAW' compose.yaml
grep -q 'network_mode: host' compose.yaml
grep -q 'read_only: true' compose.yaml
grep -q '/run:rw,nosuid,nodev,noexec' compose.yaml
grep -q 'check_pid_dir' docker/entrypoint.sh
grep -q 'no-new-privileges:true' compose.yaml
grep -q '^    cap_drop:' compose.yaml
if grep -Eiq 'privileged:[[:space:]]*true|NET_ADMIN|docker.sock|host_pid' compose.yaml; then
    echo 'Unsafe Docker Compose privilege expansion' >&2
    exit 1
fi
[ ! -e docker/uuplugin ]
[ ! -e docker/xuplugin-guardian ]
echo DOCKER_SOURCE_GUARDS_PASS
