<#
.SYNOPSIS
  Rollback do OBS via symlink: remove o link simbólico em cada perfil e restaura a pasta original a partir do backup.

.DESCRIPTION
  - Para cada perfil em C:\Users\<perfil>:
      * Remove o symlink %APPDATA%\obs-studio (se existir).
      * Se houver uma pasta real "obs-studio", renomeia para "obs-studio.pre_rollback_<ts>" (para não perder nada).
      * Procura pelo backup "obs-studio.backup_YYYYMMDD_HHMMSS" (criado no setup).
      * Restaura o backup mais recente para "obs-studio".
      * Se não houver backup, cria uma pasta vazia "obs-studio" (opcional, controlado por -CreateEmptyIfNoBackup).
  - Log em C:\ProgramData\OBS-Symlink\logs\rollback_*.log

.PARAMETER IncludeUsers
  Lista de pastas em C:\Users a incluir explicitamente.

.PARAMETER ExcludeUsers
  Lista de perfis a ignorar. Default inclui contas de sistema/comuns.

.PARAMETER WhatIf
  Simula as ações sem alterar nada.

.PARAMETER VerboseLog
  Mostra logs detalhados no console (além do arquivo).

.PARAMETER CreateEmptyIfNoBackup
  Se não houver backup, cria uma pasta vazia "obs-studio" para o perfil (evita erros ao abrir o OBS).

.EXAMPLE
  .\OBS-Symlink-Rollback.ps1 -VerboseLog

.EXAMPLE
  .\OBS-Symlink-Rollback.ps1 -IncludeUsers "Aluno1","Aluno2" -WhatIf
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
  [string[]]$IncludeUsers,
  [string[]]$ExcludeUsers = @(
    'Default','Default User','All Users','Public',
    'Administrador','Admin','WDAGUtilityAccount'
  ),
  [switch]$WhatIf,
  [switch]$VerboseLog,
  [switch]$CreateEmptyIfNoBackup
)

$ErrorActionPreference = 'Stop'

# ---------- util de log ----------
$LogRoot = "C:\ProgramData\OBS-Symlink\logs"
if (!(Test-Path $LogRoot)) { New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null }
$LogFile = Join-Path $LogRoot ("rollback_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

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

Write-Log "Iniciando rollback do OBS (symlink -> pasta original)."

# Seleção de perfis
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
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $preRollback = "${target}.pre_rollback_$timestamp"

    # 1) Se for symlink, remover
    if (Is-Symlink $target) {
      Write-Log "[$($p.Name)] Removendo symlink: $target"
      if ($PSCmdlet.ShouldProcess($target, "Remove symlink")) {
        Remove-Item $target -Force
      }
    } elseif (Test-Path $target -PathType Container) {
      # Existe pasta real — vamos preservar
      Write-Log "[$($p.Name)] Pasta real atual encontrada. Preservando como: $preRollback"
      if ($PSCmdlet.ShouldProcess("$target -> $preRollback", "Backup pre-rollback")) {
        Move-Item $target $preRollback
      }
    } elseif (Test-Path $target -PathType Leaf) {
      # Algum arquivo no lugar — preserva
      $fileBak = "${target}.pre_rollback_file_$timestamp"
      Write-Log "[$($p.Name)] Arquivo inesperado em $target. Preservando como: $fileBak"
      if ($PSCmdlet.ShouldProcess("$target -> $fileBak", "Backup file pre-rollback")) {
        Move-Item $target $fileBak
      }
    }

    # 2) Encontrar backup(s)
    $backups = Get-ChildItem -Path $roaming -Directory -Filter "obs-studio.backup_*" -ErrorAction SilentlyContinue |
               Sort-Object LastWriteTime -Descending

    if ($backups -and $backups.Count -gt 0) {
      $chosen = $backups[0]
      Write-Log "[$($p.Name)] Restaurando backup: $($chosen.FullName) -> $target"
      if ($PSCmdlet.ShouldProcess("$($chosen.FullName) -> $target", "Restore backup")) {
        Move-Item $chosen.FullName $target
      }
      Write-Log "[$($p.Name)] OK (restaurado)."
    } else {
      Write-Log "[$($p.Name)] Nenhum backup 'obs-studio.backup_*' encontrado." "WARN"
      if ($CreateEmptyIfNoBackup) {
        Write-Log "[$($p.Name)] Criando pasta vazia: $target"
        if ($PSCmdlet.ShouldProcess($target, "Create empty obs-studio")) {
          New-Item -ItemType Directory -Path $target -Force | Out-Null
        }
      } else {
        Write-Log "[$($p.Name)] **Sem backup** e **CreateEmptyIfNoBackup não usado** — OBS criará a pasta ao abrir." "WARN"
      }
    }

  } catch {
    Write-Log "[$($p.Name)] ERRO: $_" "ERROR"
  }
}

Write-Log "Rollback concluído. Log: $LogFile"
if ($WhatIf) { Write-Host "`n(MODO WHATIF – nada foi alterado)" }
else { Write-Host "`n✅ Rollback concluído. Confira o log: $LogFile" }
