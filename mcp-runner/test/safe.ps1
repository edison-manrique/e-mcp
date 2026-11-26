$ErrorActionPreference = "Continue"
$exe = Join-Path $PSScriptRoot "..\zig-out\bin\mcp-runner.exe"

function Safe-Run {
    param([string]$Json, [int]$KillAfterSec = 15)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.Write($Json + "`n")
    $p.StandardInput.Close()
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $exited = $p.WaitForExit($KillAfterSec * 1000)
    $sw.Stop()
    if ($exited) {
        $out = $p.StandardOutput.ReadToEnd()
        return "EXITED exit=$($p.ExitCode) sec=$([math]::Round($sw.Elapsed.TotalSeconds,2)) out=$out"
    } else {
        # matar arbol completo
        & taskkill /PID $p.Id /T /F 2>&1 | Out-Null
        try { $p.Kill() } catch {}
        return "HUNG (>$KillAfterSec s) killed"
    }
}

$req = @{ jsonrpc = "2.0"; id = 1; method = "tools/call"; params = @{ name = "run_code"; arguments = @{ code = 'fn main(){ loop {} }'; lang = "rust"; timeout_ms = 2000 } } }
$json = $req | ConvertTo-Json -Depth 10 -Compress
Write-Host "RUST loop timeout_ms=2000:"
Write-Host ("  " + (Safe-Run $json 15))
