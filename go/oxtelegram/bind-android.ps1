# Rebuild android/ox_tdlib_bridge/libs/oxtelegram.aar with Sushi's Seq.java patch.
# Upstream gomobile's GoRefQueue Finalizer Thread calls destroyRef off the process's
# single JNI ingress thread; that races sendText and crashes with bulkBarrierPreWrite.
# patches/Seq.java routes releases through Seq.setReleaser → ox-gomobile.
$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
$aarOut = Join-Path $here "..\..\android\ox_tdlib_bridge\libs\oxtelegram.aar"
$patchSeq = Join-Path $here "patches\Seq.java"
if (-not (Test-Path $patchSeq)) {
  throw "missing Seq.java patch: $patchSeq"
}

Push-Location $here
try {
  $modPath = (go list -m -f "{{.Dir}}" "golang.org/x/mobile").Trim()
  if (-not $modPath -or -not (Test-Path $modPath)) {
    throw "golang.org/x/mobile module dir not found (run go mod download)"
  }

  $overlay = Join-Path $env:TEMP ("oxtelegram-mobile-overlay-" + [guid]::NewGuid().ToString("n"))
  New-Item -ItemType Directory -Force -Path $overlay | Out-Null
  try {
    Write-Host "overlay: copy $modPath -> $overlay"
    # Module cache files are often ReadOnly; Copy-Item keeps that attribute.
    robocopy $modPath $overlay /E /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed exit=$LASTEXITCODE" }

    Get-ChildItem -Path $overlay -Recurse -File | ForEach-Object {
      if ($_.IsReadOnly) { $_.IsReadOnly = $false }
    }

    $overlaySeq = Join-Path $overlay "bind\java\Seq.java"
    Copy-Item -Force $patchSeq $overlaySeq
    Write-Host "overlay: installed patched Seq.java"

    $goMod = Join-Path $here "go.mod"
    $original = Get-Content -Raw $goMod
    $replaceLine = "replace golang.org/x/mobile => $($overlay.Replace('\', '/'))"
    if ($original -notmatch [regex]::Escape("replace golang.org/x/mobile")) {
      Add-Content -Path $goMod -Value "`n$replaceLine`n"
    } else {
      throw "go.mod already has a golang.org/x/mobile replace; remove it before bind-android.ps1"
    }

    try {
      Write-Host "gomobile bind -> $aarOut"
      & gomobile bind -target=android -androidapi 24 -o $aarOut .\mobile
      if ($LASTEXITCODE -ne 0) { throw "gomobile bind failed exit=$LASTEXITCODE" }
      Write-Host "ok: $aarOut"
    } finally {
      Set-Content -Path $goMod -Value $original -NoNewline
    }
  } finally {
    Remove-Item -Recurse -Force $overlay -ErrorAction SilentlyContinue
  }
} finally {
  Pop-Location
}
