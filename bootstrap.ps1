# bootstrap.ps1  (Raw: https://raw.githubusercontent.com/cpps-unesp/obs-studio/main/bootstrap.ps1)
param(
  [ValidateSet('setup','rollback')]
  [string]$Script = 'setup',           # 'setup' ou 'rollback'
  [string[]]$PassThruArgs,             # argumentos repassados ao script final
  [string]$Repo = 'cpps-unesp/obs-studio',
  [string]$Branch = 'main'
)

$ErrorActionPreference = 'Stop'

# Monta URL para o arquivo {setup|rollback}.ps1 no Raw GitHub
$base = "https://raw.githubusercontent.com/$Repo/$Branch"
$scriptName = ($Script.ToLower() + '.ps1')
$scriptUrl = "$base/$scriptName"

# Baixa para TEMP com cache-buster
$tmp = Join-Path $env:TEMP ("obs_{0}_{1}.ps1" -f $Script, (Get-Random))
$dlUrl = "$scriptUrl?nocache=$(Get-Random)"

Write-Host "[bootstrap] Baixando $scriptName de $dlUrl ..."
Invoke-WebRequest -Uri $dlUrl -OutFile $tmp -UseBasicParsing

Write-Host "[bootstrap] Executando $scriptName ..."
& powershell -NoProfile -ExecutionPolicy Bypass -File $tmp @PassThruArgs
