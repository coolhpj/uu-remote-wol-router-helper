# Windows setup companion. Copies router-side shell sources only.
# It does not install NetEase UU, persistently change firmware or save SSH passwords.
[CmdletBinding()]
param(
    [string]$RouterHost,
    [string]$RouterUser = 'root',
    [ValidateRange(1,65535)][int]$Port = 22,
    [switch]$Preview
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$remoteDir = '/tmp/uu-remote-wol-router-helper'

function Fail([string]$Message) { throw $Message }
function Assert-HostName([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value.Length -gt 253 -or
        $Value -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]*$' -or
        $Value -match '\.\.' -or $Value -match '\.$') {
        Fail '路由器地址无效。请输入 IPv4 地址或普通主机名（例如 router.example.invalid）。'
    }
}
function Assert-UserName([string]$Value) {
    if ($Value -notmatch '^[A-Za-z_][A-Za-z0-9_.-]{0,31}$') {
        Fail '用户名格式无效。请使用路由器系统已有的 SSH 登录用户名。'
    }
}
function Show-Stage([string]$Title) {
    Write-Host ""
    Write-Host ("  {0}" -f $Title) -ForegroundColor Cyan
}
function Invoke-Checked([string]$Program, [string[]]$Arguments, [string]$FriendlyError) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) {
        Fail ("{0}（退出码 {1}）。未执行后续操作。" -f $FriendlyError, $LASTEXITCODE)
    }
}
if ([string]::IsNullOrWhiteSpace($RouterHost)) {
    if ($Preview) { Fail '预览模式需要提供 -RouterHost，例如 -RouterHost router.example.invalid。' }
    $RouterHost = Read-Host '请输入路由器 IP 或主机名'
}
Assert-HostName $RouterHost
Assert-UserName $RouterUser
$target = "${RouterUser}@${RouterHost}"
Write-Host ''
Write-Host '  UU REMOTE  |  Windows 路由器连接助手' -ForegroundColor Cyan
Write-Host '  连接路由器 → 上传助手 → 打开操作菜单'
Write-Host ("  路由器：{0}  端口：{1}" -f $target, $Port)
Write-Host '  这里只上传助手并打开菜单，不会安装网易插件、刷机或保存密码。'
Write-Host '  首次连接须自行核实 SSH 服务器指纹。'
if ($Preview) {
    Write-Host ''
    Write-Host '  预览：检查、上传和连接操作均未执行。'
    Write-Host ("  项目目录：{0}" -f $repoRoot)
    Write-Host ("  远端临时位置：{0}" -f $remoteDir)
    Write-Host '  实际运行仅复制 uu-helper.sh、lib、scripts、platforms 四部分。'
    return
}
foreach ($part in @('uu-helper.sh','lib','scripts','platforms')) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $part))) {
        Fail ("项目文件不完整：缺少 {0}。请重新下载 GitHub 仓库 ZIP。" -f $part)
    }
}
$ssh = Get-Command ssh.exe -ErrorAction SilentlyContinue
$scp = Get-Command scp.exe -ErrorAction SilentlyContinue
if (-not $ssh -or -not $scp) {
    Fail 'Windows 未找到系统 OpenSSH 客户端（ssh.exe / scp.exe）。请在 Windows 可选功能中安装 OpenSSH 客户端，或使用 WinSCP 手动上传。'
}
Write-Host ''
Write-Host '  说明：上传和登录使用独立 SSH 连接，可能需要多次输入路由器密码。'
Write-Host '  请先开启路由器 SSH，并准备好管理员登录信息。'
$choice = Read-Host '已准备好路由器管理员账号？输入 1 开始（回车取消）'
if ($choice -ne '1') {
    Write-Host '已取消，没有连接或修改路由器。'
    return
}
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("uu-router-upload-" + [guid]::NewGuid().ToString('N'))
$bundle = Join-Path $tempRoot 'uu-remote-wol-router-helper'
try {
    New-Item -ItemType Directory -Path $bundle -Force | Out-Null
    foreach ($part in @('uu-helper.sh','lib','scripts','platforms')) {
        Copy-Item -LiteralPath (Join-Path $repoRoot $part) -Destination $bundle -Recurse -Force
    }
    Show-Stage '[1/3] 检查路由器连接'
    $prepare = "if [ -e /tmp/uu-wol-helper-stage/mips-smoke.lock ]; then echo '有未完成的 MIPS 测试清理，停止上传'; exit 65; fi; mkdir -p $remoteDir"
    Invoke-Checked $ssh.Source @('-p', "$Port", $target, $prepare) '路由器连接或临时目录准备失败'
    Show-Stage '[2/3] 上传必要文件'
    # Legacy SCP (-O) supports Dropbear/OpenWrt without SFTP.
    $localContents = Join-Path $bundle '.'
    Invoke-Checked $scp.Source @('-O','-r','-P',"$Port",$localContents,"${target}:${remoteDir}/") '上传失败。精简 OpenWrt 通常需要支持 -O 的 OpenSSH；也可用 WinSCP 手动上传'
    Show-Stage '[3/3] 打开路由器操作菜单'
    Write-Host '  已准备打开菜单。后续按数字选择操作，未经确认不会安装插件。'
    Invoke-Checked $ssh.Source @('-t','-p',"$Port",$target,"cd $remoteDir && test -f uu-helper.sh && sh uu-helper.sh start") 'SSH 会话或菜单退出时出现错误'
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
