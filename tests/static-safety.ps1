$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$shippedLua = Get-ChildItem -LiteralPath $root -File -Recurse -Filter "*.lua" |
    Where-Object {
        $_.FullName -notlike (Join-Path $root "Libs\*") -and
        $_.FullName -notlike (Join-Path $root "tests\*")
    }

$forbidden = @(
    "AcceptSpellConfirmationPrompt",
    "DeclineSpellConfirmationPrompt",
    "RollButton:Click(",
    "PassButton:Click(",
    "/bbr roll",
    "/bbr decline"
)

$violations = @()
foreach ($needle in $forbidden) {
    $matches = $shippedLua | Select-String -SimpleMatch -Pattern $needle
    if ($matches) {
        $violations += $matches
    }
}

$controllerPath = Join-Path $root "RollController.lua"
$controller = Get-Content -LiteralPath $controllerPath
$passInvocations = $controller | Select-String -Pattern "nativePassOnClick\s*\("
if ($passInvocations) {
    $violations += $passInvocations
}

$nativeInvocation = $controller | Select-String -SimpleMatch -Pattern "callback(button, mouseButton, down)"
if ($nativeInvocation.Count -ne 1) {
    throw "Expected exactly one native Roll callback invocation site; found $($nativeInvocation.Count)."
}

$invocationLine = $nativeInvocation.LineNumber
$authorizationConsumed = $false
for ($line = [Math]::Max(1, $invocationLine - 12); $line -lt $invocationLine; $line++) {
    if ($controller[$line - 1] -match "^\s*armedToken\s*=\s*nil\s*$") {
        $authorizationConsumed = $true
        break
    }
}
if (-not $authorizationConsumed) {
    throw "The one-shot authorization is not visibly consumed before the native Roll callback."
}

if ($violations.Count -gt 0) {
    $violations | ForEach-Object { Write-Error $_.ToString() }
    throw "Bonus-roll safety scan failed."
}

Write-Output "Static safety scan passed for $($shippedLua.Count) shipped addon Lua files."
