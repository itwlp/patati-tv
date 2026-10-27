#Requires -Version 7.0
<#
.SYNOPSIS
  Renova o plano semanal de Patati Patatá e publica em https://itwlp.github.io/patati-tv/.

.DESCRIPTION
  Roda no Windows do notebook (sem o app Claude, sem sandbox): chama a skill patati-curadoria
  (curadoria.py) com o histórico guardado em dados\ (local, nunca vai ao GitHub), copia o plano
  para plano.json e, se mudou, faz commit e push. Registra tudo em logs\log-plano-<data>.csv.

  Para atualizar o histórico: exporte de novo as coleções do painel para dados\ (ver SKILL.md).
  Sem histórico novo o plano ainda funciona; só o ranking por afinidade fica um pouco defasado.

.PARAMETER Simular
  Mostra o que faria sem gravar nem publicar (equivale a -WhatIf).
.PARAMETER SemPush
  Grava e faz commit, mas não envia ao GitHub.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Simular,
    [switch]$SemPush,
    [int]$Dias = 7,
    [string]$Log = (Join-Path $PSScriptRoot "logs\log-plano-$(Get-Date -Format 'yyyy-MM-dd').csv")
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($Simular) { $WhatIfPreference = $true }

$registro = [System.Collections.Generic.List[object]]::new()
function Add-Registro { param([string]$Item, [string]$Acao, [string]$Situacao, [string]$Detalhe = '')
    $registro.Add([pscustomobject]@{ Quando = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); Item = $Item; Acao = $Acao; Situacao = $Situacao; Detalhe = $Detalhe })
    Write-Output ("{0,-9} {1,-10} {2}  {3}" -f $Situacao, $Acao, $Item, $Detalhe) }

$raiz = $PSScriptRoot
$script = Join-Path $HOME '.claude\skills\patati-curadoria\scripts\curadoria.py'
$dados = Join-Path $raiz 'dados'
$saida = Join-Path $raiz 'saida'
$destino = Join-Path $raiz 'plano.json'

try {
    $env:PATH = [Environment]::GetEnvironmentVariable('PATH', 'User') + ';' + [Environment]::GetEnvironmentVariable('PATH', 'Machine')
    if (-not (Test-Path -LiteralPath $script)) { throw "Script da skill não encontrado: $script" }
    if (-not (Get-Command yt-dlp -ErrorAction SilentlyContinue)) { throw 'yt-dlp não encontrado (winget install yt-dlp.yt-dlp)' }
    $py = Get-Command python -ErrorAction SilentlyContinue
    if (-not $py) { throw 'python não encontrado' }
    if (-not (Test-Path -LiteralPath $dados)) { New-Item -ItemType Directory -Path $dados -Force | Out-Null; Add-Registro 'dados' 'criar' 'AVISO' 'sem histórico local; o plano sai sem ranking por afinidade' }

    $hoje = Get-Date -Format 'yyyy-MM-dd'
    $out = & $py.Source -X utf8 $script --historico $dados --saida $saida --dias $Dias --meta-min 60 --faixa-min 10 --faixa-max 20 --inicio $hoje 2>&1
    if ($LASTEXITCODE -ne 0) { throw "curadoria.py saiu com código ${LASTEXITCODE}: $(($out | Select-Object -Last 3) -join ' ')" }
    $novo = Join-Path $saida 'painel-plano.json'
    $p = Get-Content -LiteralPath $novo -Raw -Encoding UTF8 | ConvertFrom-Json
    $fora = @($p.dias | Where-Object { $_.total_min -lt 52 -or $_.total_min -gt 68 })
    Add-Registro 'plano' 'gerar' $(if ($p.dias.Count -eq $Dias -and $fora.Count -eq 0) { 'OK' } else { 'AVISO' }) "$($p.dias.Count) dias; $($fora.Count) fora de 52-68 min"
    if ($p.dias.Count -ne $Dias) { throw "plano com $($p.dias.Count) dias, esperado $Dias; nada publicado" }

    $igual = (Test-Path -LiteralPath $destino) -and ((Get-FileHash -LiteralPath $novo).Hash -eq (Get-FileHash -LiteralPath $destino).Hash)
    if ($igual) { Add-Registro 'plano.json' 'gravar' 'IGUAL' 'sem mudanças' }
    elseif ($PSCmdlet.ShouldProcess($destino, 'gravar plano.json')) {
        Copy-Item -LiteralPath $novo -Destination $destino -Force
        Add-Registro 'plano.json' 'gravar' 'OK' $destino
        & git -C $raiz add plano.json index.html 2>&1 | Out-Null
        & git -C $raiz commit -q -m "plano: semana de $hoje" 2>&1 | Out-Null
        Add-Registro 'git' 'commit' $(if ($LASTEXITCODE -eq 0) { 'OK' } else { 'AVISO' }) "código $LASTEXITCODE"
        if ($SemPush) { Add-Registro 'git' 'push' 'PULADO' '-SemPush' }
        else {
            $r = & git -C $raiz push -q 2>&1
            Add-Registro 'git' 'push' $(if ($LASTEXITCODE -eq 0) { 'OK' } else { 'ERRO' }) ("$r" -replace "`n", ' ')
        }
    } else { Add-Registro 'plano.json' 'gravar' 'SIMULADO' $destino }
} catch {
    Add-Registro 'execução' 'rodar' 'ERRO' $_.Exception.Message
}

$pastaLog = Split-Path -Parent $Log; if (-not (Test-Path -LiteralPath $pastaLog)) { New-Item -ItemType Directory -Path $pastaLog -Force | Out-Null }
$registro | Export-Csv -LiteralPath $Log -NoTypeInformation -Encoding UTF8 -Append
if (@($registro | Where-Object Situacao -eq 'ERRO').Count) { exit 1 }
