# Windows-latest only. Never connects to a real router.
$ErrorActionPreference = 'Stop'
$launcher = Join-Path (Split-Path -Parent $PSScriptRoot) 'tools\windows-launcher.ps1'
$ps = (Get-Command powershell.exe -ErrorAction Stop).Source
function Assert([bool]$Condition,[string]$Description) {
    if (-not $Condition) { throw "FAILED: $Description" }
    Write-Host "ok - $Description"
}
function Call-Launcher([string[]]$Arguments) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $ps -NoProfile -ExecutionPolicy Bypass -File $launcher @Arguments 2>&1 | Out-String
        return @{ Result=$output; Exit=$LASTEXITCODE }
    } finally { $ErrorActionPreference = $old }
}
$valid = Call-Launcher @('-Preview','-RouterHost','router.example.invalid')
Assert ($valid.Exit -eq 0 -and $valid.Result.Contains('预览：检查、上传和连接操作均未执行')) 'valid preview without network activity'
Assert ($valid.Result.Contains('lib、scripts、platforms')) 'preview describes minimal upload'
$invalid = Call-Launcher @('-Preview','-RouterHost','router.example.invalid;echo PWNED')
Assert ($invalid.Exit -ne 0 -and $invalid.Result.Contains('路由器地址无效')) 'router host injection refused'
$badUser = Call-Launcher @('-Preview','-RouterHost','router.example.invalid','-RouterUser','root;reboot')
Assert ($badUser.Exit -ne 0 -and $badUser.Result.Contains('用户名格式无效')) 'SSH user injection refused'
$missing = Call-Launcher @('-Preview')
Assert ($missing.Exit -ne 0) 'unattended preview without host refused'
$badPort = Call-Launcher @('-Preview','-RouterHost','router.example.invalid','-Port','65536')
Assert ($badPort.Exit -ne 0) 'invalid port refused'

# Full mocked flow: local dummy ssh.exe and scp.exe do not use any network.
# If lookup fails, .invalid DNS prevents reaching a real router.
$temp = Join-Path ([IO.Path]::GetTempPath()) ('uu-win-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -Path $temp -ItemType Directory | Out-Null
$priorPath = $env:PATH
try {
    $fake = Join-Path $temp 'fake-bin'
    New-Item -Path $fake -ItemType Directory | Out-Null
    $program = @'
using System;
using System.IO;
public class FakeSshScp {
    public static int Main(string[] args) {
        string log = Environment.GetEnvironmentVariable("UU_TEST_CALLS");
        string binary = Path.GetFileName(System.Reflection.Assembly.GetExecutingAssembly().Location);
        File.AppendAllText(log, binary + "|" + String.Join("|", args) + Environment.NewLine);
        return 0;
    }
}
'@
    Add-Type -TypeDefinition $program -OutputAssembly (Join-Path $fake 'ssh.exe') -OutputType ConsoleApplication
    Copy-Item -LiteralPath (Join-Path $fake 'ssh.exe') -Destination (Join-Path $fake 'scp.exe')
    $env:UU_TEST_CALLS = Join-Path $temp 'calls.txt'
    $env:PATH = "$fake;$priorPath"
    $inputPath = Join-Path $temp 'confirmation.txt'
    $stdout = Join-Path $temp 'stdout.txt'
    $stderr = Join-Path $temp 'stderr.txt'
    [IO.File]::WriteAllText($inputPath, ('1' + [Environment]::NewLine), [Text.Encoding]::ASCII)
    $launchArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"' + $launcher + '"'),'-RouterHost','router.example.invalid')
    $process = Start-Process -FilePath $ps -ArgumentList $launchArgs -RedirectStandardInput $inputPath -RedirectStandardOutput $stdout -RedirectStandardError $stderr -Wait -PassThru
    $runError = [IO.File]::ReadAllText($stderr)
    Assert ($process.ExitCode -eq 0) ("mock launch success: $runError")
    Assert (Test-Path $env:UU_TEST_CALLS) 'fake tools were selected'
    $calls = @([IO.File]::ReadAllLines($env:UU_TEST_CALLS))
    Assert ($calls.Count -eq 3) 'exactly three transport invocations'
    Assert ($calls[0].StartsWith('ssh.exe|') -and $calls[0].Contains('mkdir -p /tmp/uu-remote-wol-router-helper')) 'first SSH prepares only temp directory'
    Assert ($calls[1].StartsWith('scp.exe|') -and $calls[1].Contains('|-O|-r|-P|22|')) 'Dropbear-compatible SCP selected'
    Assert ($calls[1].Contains(':/tmp/uu-remote-wol-router-helper/')) 'upload uses fixed remote temp path'
    Assert ($calls[2].StartsWith('ssh.exe|') -and $calls[2].Contains('sh uu-helper.sh start')) 'last SSH starts interactive menu'
} finally {
    $env:PATH = $priorPath
    Remove-Item Env:\UU_TEST_CALLS -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host 'all Windows launcher tests passed'
# PowerShell 5.1 keeps LASTEXITCODE from intentional negative child tests.
# Explicit success status prevents GitHub's runner wrapper from inheriting it.
exit 0
