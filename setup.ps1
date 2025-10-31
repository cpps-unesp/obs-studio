<# 
.SYNOPSIS
  Centraliza a configuração do OBS Studio via symlink para múltiplos usuários no Windows 11.

.DESCRIPTION
  - Cria/usa um diretório compartilhado (local ou UNC) com a pasta "obs-studio".
  - Para cada perfil em C:\Users\<perfil>, substitui %APPDATA%\obs-studio por um link simbólico apontando para o compartilhado.
  - Faz backup automático da pasta existente do usuário antes de trocar por symlink.
  - Permite semear o diretório compartilhado a partir da config do usuário atual (opcional).
  - Gera logs em C:\ProgramData\OBS-Symlink\logs\.

.PARAMETER SharedPath
  Caminho completo para a pasta compartilhada final "obs-studio".
  Exemplos:
    D:\OBS_Config\obs-studio
    \\servidor\comp\OBS_Config\obs-studio

.PARAMETER SeedFromCurrent
  Se informado, copia a configuração do usuário atual (%APPDATA%\obs-studio) para o compartilhado,
  mas somente se o compartilhado estiver vazio.

.PARAMETER IncludeUsers
  Lista de *nomes* de perfis (pastas em C:\Users) para incluir explicitamente. Se omitido, aplica em todos (menos os excluídos).

.PARAMETER ExcludeUsers
  Lista de perfis a ignorar. Um conjunto padrão seguro já vem preenchido.

.PARAMETER WhatIf
  Executa em modo de simulação (não altera nada), apenas imprime o que faria.

.PARAMETER VerboseLog
  Imprime detalhes extras no console além do log em arquivo.

.EXAMPLE
  .\OBS-Symlink-Setup.ps1 -SharedPath "D:\OBS_Config\obs-studio" -SeedFromCurrent

.EXAMPLE
  .\OBS-Symlink-Setup.ps1 -SharedPath "\\FS01\OBS\obs-studio" -IncludeUsers "Aluno1","Aluno2" -WhatIf

#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
  [Parameter(Mandatory=$true)]
  [string]$SharedPath,

  [switch]$SeedFromCurrent,

  [string[]]$IncludeUsers,

  [string[]]$ExcludeUsers = @(
    'Default','Default User','All Users','Public',
    'Administrador','Admin','WDAGUtilityAccount'
  ),

  [switch]$WhatIf,

  [switch]$VerboseLog
)

$ErrorActionPreference = 'Stop'

# ---------- Utilidades de log ----------
$LogRoot = "C:\ProgramData\OBS-Symlink\logs"
if (!(Test-Path $LogRoot)) { New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null }
$LogFile = Join-Path $LogRoot ("setup_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

function Write-Log {
  param([string]$Message, [string]$Level = "INFO")
  $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
  Add-Content -Path $LogFile -Value $line
  if ($VerboseLog -or $Level -in @('WARN','ERROR')) { Write-Host $line }
}

function Is-Symlink {
  param([string]$Path)
  if (!(Test-Path $Path)) { return $false }
  try {
    $attr = (Get-Item $Path -Force).Attributes
    return ($attr -band [IO.FileAttributes]::ReparsePoint) -ne 0
  } catch { return $false }
}

function Ensure-Directory {
  param([string]$Path)
  if (!(Test-Path $Path)) {
    if ($PSCmdlet.ShouldProcess($Path, "Create directory")) {
      New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
  }
}

# ---------- Valida SharedPath ----------
if ($SharedPath.TrimEnd('\') -match '\\\\[^\\]') {
  # ok: UNC
} else {
  # local drive ou caminho normal
}

# Garante que SharedPath termina com "obs-studio"
if (-not ($SharedPath.TrimEnd('\') -match '(?i)\\obs-studio$')) {
  # Se passaram só "D:\OBS_Config", anexamos "obs-studio"
  $SharedPath = Join-Path $SharedPath 'obs-studio'
}

Write-Log "Usando SharedPath: $SharedPath"

# Cria pasta compartilhada (e pai) se necessário
$SharedParent = Split-Path $SharedPath -Parent
Ensure-Directory $SharedParent
Ensure-Directory $SharedPath

# Permissões: concede Modify para grupo BUILTIN\Users (SID: S-1-5-32-545)
if ($PSCmdlet.ShouldProcess($SharedParent, "Grant Modify to BUILTIN\Users recursively")) {
  try {
    icacls $SharedParent /grant *S-1-5-32-545:(OI)(CI)M /T | Out-Null
    Write-Log "Permissões aplicadas (Modify) para Users em $SharedParent"
  } catch {
    Write-Log "Falha ao aplicar permissões em $SharedParent: $_" "WARN"
  }
}

# (Opcional) Semeia config do usuário atual
$CurrentUserCfg = Join-Path $env:APPDATA "obs-studio"
$sharedEmpty = -not (Get-ChildItem -Path $SharedPath -Force -ErrorAction SilentlyContinue | Select-Object -First 1)

if ($SeedFromCurrent -and $sharedEmpty -and (Test-Path $CurrentUserCfg)) {
  Write-Log "Semear do usuário atual: copiando $CurrentUserCfg -> $SharedPath"
  if ($PSCmdlet.ShouldProcess("$CurrentUserCfg -> $SharedPath", "Seed config with robocopy")) {
    robocopy $CurrentUserCfg $SharedPath /E /XO /R:1 /W:2 /NFL /NDL /NP | Out-Null
  }
} elseif ($SeedFromCurrent -and -not $sharedEmpty) {
  Write-Log "SeedFromCurrent solicitado, mas o compartilhado NÃO está vazio — semear ignorado." "WARN"
}

# Lista de perfis alvo
$profiles = Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue
if ($IncludeUsers) {
  $profiles = $profiles | Where-Object { $_.Name -in $IncludeUsers }
} else {
  $profiles = $profiles | Where-Object { $ExcludeUsers -notcontains $_.Name }
}

if (-not $profiles) {
  Write-Log "Nenhum perfil alvo encontrado. Encerrando." "ERROR"
  throw "Nenhum perfil para processar."
}

Write-Log ("Perfis alvo: " + ($profiles.Name -join ', '))

foreach ($p in $profiles) {
  try {
    $roaming = Join-Path $p.FullName "AppData\Roaming"
    if (!(Test-Path $roaming)) {
      Write-Log "Roaming não existe para $($p.Name): $roaming — pulando." "WARN"
      continue
    }

    $target = Join-Path $roaming "obs-studio"
    $backup = "${target}.backup_{0}" -f (Get-Date -Format 'yyyyMMdd_HHmmss')

    # Se já é symlink -> recria (opcional) ou mantém
    if (Is-Symlink $target) {
      Write-Log "[$($p.Name)] Já é symlink: $target -> recriando para garantir consistência."
      if ($PSCmdlet.ShouldProcess($target, "Remove existing symlink")) {
        Remove-Item $target -Force
      }
    } elseif (Test-Path $target -PathType Container) {
      # Pasta real: backup antes de substituir
      Write-Log "[$($p.Name)] Backup da pasta real: $target -> $backup"
      if ($PSCmdlet.ShouldProcess("$target -> $backup", "Backup user config")) {
        Move-Item $target $backup
      }
    } elseif (Test-Path $target -PathType Leaf) {
      # É um arquivo? Renomeia/backup
      $fileBak = "${target}.bak_{0}" -f (Get-Date -Format 'yyyyMMdd_HHmmss')
      Write-Log "[$($p.Name)] Havia um arquivo em $target. Backup: $fileBak"
      if ($PSCmdlet.ShouldProcess("$target -> $fileBak", "Backup file")) {
        Move-Item $target $fileBak
      }
    }

    # Garante que pai exista (já existe)
    # Cria symlink (diretório) usando MKLINK para máxima compatibilidade
    Write-Log "[$($p.Name)] Criando symlink: $target -> $SharedPath"
    if ($PSCmdlet.ShouldProcess("$target", "mklink /D")) {
      cmd /c "mklink /D `"$target`" `"$SharedPath`"" | Out-Null
    }

    Write-Log "[$($p.Name)] OK"

  } catch {
    Write-Log "[$($p.Name)] ERRO: $_" "ERROR"
  }
}

Write-Log "Concluído. Log em: $LogFile"
if ($WhatIf) { Write-Host "`n(MODO WHATIF – nada foi alterado)" }
else { Write-Host "`n✅ Pronto! Config centralizada em: $SharedPath`nLog: $LogFile" }
