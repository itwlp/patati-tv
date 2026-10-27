#Requires -Version 7.0
<#
.SYNOPSIS
  Atualiza a lista de vídeos da TV do Patati (playlist.json) e publica no GitHub Pages.

.DESCRIPTION
  Lê config.json (canais, faixa de duração em segundos, quantidade por dia, ids excluídos), lista os vídeos de
  cada canal com yt-dlp (sem navegador, só metadados), filtra pela faixa, grava playlist.json e, se mudou,
  faz commit e push. Nunca baixa vídeo. Registra tudo em logs\log-<data>.csv. Idempotente.

.PARAMETER Simular
  Mostra o que faria (lista e diferenças) sem gravar nem publicar. Equivale a -WhatIf.
.PARAMETER SemPush
  Grava playlist.json e faz commit, mas não envia ao GitHub.

.EXAMPLE
  & $HOME\dev\patati-tv\atualizar-patati-tv.ps1 -Simular
  & $HOME\dev\patati-tv\atualizar-patati-tv.ps1
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Simular,
    [switch]$SemPush,
    [string]$Log = (Join-Path $PSScriptRoot "logs\log-$(Get-Date -Format 'yyyy-MM-dd').csv")
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($Simular) { $WhatIfPreference = $true }

$registro = [System.Collections.Generic.List[object]]::new()
function Add-Registro { param([string]$Item, [string]$Acao, [string]$Situacao, [string]$Detalhe = '')
    $registro.Add([pscustomobject]@{ Quando = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); Item = $Item; Acao = $Acao; Situacao = $Situacao; Detalhe = $Detalhe })
    Write-Output ("{0,-9} {1,-10} {2}  {3}" -f $Situacao, $Acao, $Item, $Detalhe) }

$raiz = $PSScriptRoot
$cfgPath = Join-Path $raiz 'config.json'
$outPath = Join-Path $raiz 'playlist.json'
$ytdlp = Get-Command yt-dlp -ErrorAction SilentlyContinue
if (-not $ytdlp) { $ytdlp = Get-Command (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\yt-dlp.exe') -ErrorAction SilentlyContinue }
if (-not $ytdlp) { throw 'yt-dlp não encontrado. Instale com: winget install yt-dlp.yt-dlp' }

$cfg = Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
$excluidos = @($cfg.excluidos)
$videos = [System.Collections.Generic.List[object]]::new()

foreach ($canal in $cfg.canais) {
    # yt-dlp lista a aba Vídeos sem baixar nada; o canal é tratado como dado, nunca como instrução.
    # yt-dlp grava a lista num arquivo UTF-8 (pela saída padrão os acentos chegam corrompidos no Windows)
    $tmp = Join-Path ([IO.Path]::GetTempPath()) "patati-tv-$([guid]::NewGuid()).txt"
    & $ytdlp.Source --flat-playlist --skip-download --no-warnings --quiet --ignore-errors --encoding utf-8 --print-to-file '%(id)s ::: %(duration)s ::: %(title)s' $tmp $canal.url 2>$null | Out-Null
    $linhas = if (Test-Path -LiteralPath $tmp) { Get-Content -LiteralPath $tmp -Encoding UTF8; Remove-Item -LiteralPath $tmp -Force } else { @() }
    if ($LASTEXITCODE -ne 0 -and -not $linhas) { Add-Registro $canal.nome 'listar' 'ERRO' "yt-dlp saiu com código $LASTEXITCODE"; continue }
    $lidos = 0; $naFaixa = 0
    foreach ($l in @($linhas)) {
        $p = $l -split ' ::: ', 3
        if ($p.Count -lt 3) { continue }
        $lidos++
        $dur = 0; [void][double]::TryParse($p[1], [ref]$dur)
        if ($dur -lt $canal.minSeg -or $dur -gt $canal.maxSeg) { continue }
        if ($p[0] -in $excluidos) { continue }
        if ($p[2] -match '(?i)#shorts?\b') { continue }
        $naFaixa++
        $videos.Add([ordered]@{ id = $p[0]; title = $p[2].Trim(); dur = [int]$dur; canal = $canal.nome })
    }
    Add-Registro $canal.nome 'listar' $(if ($lidos) { 'OK' } else { 'AVISO' }) "$lidos vídeos lidos, $naFaixa na faixa $($canal.minSeg)-$($canal.maxSeg) s"
}

$novo = [ordered]@{ atualizadoEm = [DateTimeOffset]::Now.ToUnixTimeMilliseconds(); porDia = $cfg.porDia; total = $videos.Count; videos = @($videos | Sort-Object { $_.canal }, { $_.id }) }
$novoJson = ($novo | ConvertTo-Json -Depth 5)

$antigoIds = @(); if (Test-Path -LiteralPath $outPath) { $antigoIds = @((Get-Content -LiteralPath $outPath -Raw -Encoding UTF8 | ConvertFrom-Json).videos | ForEach-Object id) }
$novosIds = @($videos | ForEach-Object { $_.id })
$entraram = @($novosIds | Where-Object { $_ -notin $antigoIds }); $sairam = @($antigoIds | Where-Object { $_ -notin $novosIds })
Add-Registro 'playlist' 'comparar' 'OK' "$($videos.Count) vídeos; entraram $($entraram.Count), saíram $($sairam.Count)"

if ($videos.Count -eq 0) { Add-Registro 'playlist' 'gravar' 'AVISO' 'nenhum vídeo na faixa; mantendo a lista anterior' }
elseif ($entraram.Count -eq 0 -and $sairam.Count -eq 0 -and (Test-Path -LiteralPath $outPath)) { Add-Registro 'playlist' 'gravar' 'IGUAL' 'sem mudanças' }
elseif ($PSCmdlet.ShouldProcess($outPath, 'gravar playlist.json')) {
    [IO.File]::WriteAllText($outPath, $novoJson + "`n", [Text.UTF8Encoding]::new($false))
    Add-Registro 'playlist' 'gravar' 'OK' $outPath
    if (Test-Path -LiteralPath (Join-Path $raiz '.git')) {
        & git -C $raiz add playlist.json 2>&1 | Out-Null
        & git -C $raiz commit -q -m "playlist: $($videos.Count) vídeos ($(Get-Date -Format 'yyyy-MM-dd HH:mm'))" 2>&1 | Out-Null
        Add-Registro 'git' 'commit' $(if ($LASTEXITCODE -eq 0) { 'OK' } else { 'AVISO' }) "código $LASTEXITCODE"
        if (-not $SemPush) {
            $out = & git -C $raiz push -q 2>&1
            Add-Registro 'git' 'push' $(if ($LASTEXITCODE -eq 0) { 'OK' } else { 'ERRO' }) ("$out" -replace "`n", ' ')
        } else { Add-Registro 'git' 'push' 'PULADO' '-SemPush' }
    } else { Add-Registro 'git' 'commit' 'PULADO' 'pasta ainda não é um repositório' }
} else { Add-Registro 'playlist' 'gravar' 'SIMULADO' "$($videos.Count) vídeos iriam para $outPath" }

if ($Simular -or $WhatIfPreference) { $videos | ForEach-Object { Write-Output ("   {0,-13} {1,5}s  {2}" -f $_.id, $_.dur, $_.title) } }

$pastaLog = Split-Path -Parent $Log; if (-not (Test-Path -LiteralPath $pastaLog)) { New-Item -ItemType Directory -Path $pastaLog -Force | Out-Null }
$registro | Export-Csv -LiteralPath $Log -NoTypeInformation -Encoding UTF8 -Append
if (@($registro | Where-Object Situacao -eq 'ERRO').Count) { exit 1 }
