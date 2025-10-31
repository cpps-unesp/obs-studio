# Configurações para OBS Studio

Automatização de configurações do OBS Studio

## Pré-requisitos

:white_check_mark: Windows 11
:white_check_mark: Executar PowerShell como Administrador
:white_check_mark: Definir uma pasta compartilhada local ou em rede para a configuração
:white_check_mark: Todos os usuários precisam de permissão de escrita nessa pasta


## O que fica compartilhado?

 Ao apontar` %APPDATA%\obs-studio` para um local comum, todos passam a usar os mesmos:

 :white_check_mark: Coleções de Cenas: basic\scenes\*.json

:white_check_mark: Perfis (resoluções, FPS, destino de stream local, etc.): basic\profiles\*

:white_check_mark: Hotkeys e ajustes gerais: global.ini, basic\ui.ini, service.json, etc.

:white_check_mark: Scripts do OBS: scripts\*

:white_check_mark: Plugins binários (DLLs) normalmente ficam em C:\Program Files\obs-studio\obs-plugins e permanecem por máquina. Se você usa plugins que guardam configs em `%APPDATA%\obs-studio\plugins`, essas configs serão compartilhadas (o que geralmente é desejado).

## Como usar


- Abra PowerShell como Administrador

- Habilite a execução temporária e rode o script com o comando abaixo:

```
Set-ExecutionPolicy Bypass -Scope Process -Force
```

- Rode o script:

```
# Exemplo local
.\OBS-Symlink-Setup.ps1 -SharedPath "D:\OBS_Config\obs-studio" -SeedFromCurrent

```


### Parâmetros úteis

-`SeedFromCurrent`: copia sua config atual para o compartilhado se ele estiver vazio.

-`IncludeUsers` "Aluno1","Aluno2": aplica apenas a esses perfis (pastas em C:\Users).

-`WhatIf`: simulação; imprime o que faria sem alterar nada.

-`VerboseLog`: log detalhado também no console.

O script gera logs em: C:\ProgramData\OBS-Symlink\logs\setup_YYYYMMDD_HHMMSS.log













## Inspirações

- https://github.com/Matishzz/OBS-Studio

