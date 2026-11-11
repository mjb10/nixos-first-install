# Changelog

Historial de cambios de `nixos-first-install`.

- **Orden:** lo más nuevo arriba de todo; hacia abajo, lo más viejo (también dentro de cada día).
- **Fechas:** `AAAA-MM-DD`, hora de Argentina (UTC−03:00), tomadas de `git log --date=iso`.
- **Formato:** `hash` — **Área:** descripción de lo que cambió **en el código**. Áreas: **Scripts** (los `install-*.sh`), **README**, **Docs** (`AGENTS.md`, `CHANGELOG.md`, `CLAUDE.md`).
- ⚠️ marca los commits cuyo mensaje no coincide con el diff: confiá en la descripción de acá, no en el mensaje.
- "4 scripts" = `install-mbr.sh`, `install-gpt.sh`, `install-mbr-for-pc.sh` e `install-gpt-for-pc.sh`.
- No hay versiones ni tags: `main` es lo que se descarga con `curl`.

Reglas de mantenimiento: ver [`AGENTS.md` §13](AGENTS.md#13-mantenimiento-de-changelogmd).

---

## 2026-11-11

- **(sin commitear)** — **Scripts (4):** `createKeys` reinicia solo si `update` terminó bien (`if update; then … fi`). Antes ignoraba el resultado: si `nixos-rebuild` fallaba (rama inexistente, deploy key sin cargar, perfil que no existe), igual mostraba *"Actualización completada."* y reiniciaba a los 5 segundos con la configuración del instalador, sin aplicar la del flake. Ahora, si falla, muestra *"La actualización falló: no se reinicia el sistema."*, sugiere reintentar con `update && sudo reboot` y sale con código 1. **README:** el paso 4 de VPS explica qué hacer si falla. **Docs:** `AGENTS.md` §3 (Fase 3), §6.5, P5 y §11.
- **(sin commitear)** — **Scripts (4):** `update` pide el nombre de la rama del repo del flake (*"Poner nombre de la rama del repositorio. / Si esta vacio, por defecto se usará la principal del repo."*, con `read … rama < /dev/tty`) y arma la URL en la variable `repo` con un `if`: si se ingresó una rama, `git+ssh://<url>?ref=<rama>#<perfil>`; si quedó vacía, `git+ssh://<url>#<perfil>`, sin `?ref=`, y Nix usa la rama por defecto del repo. `nixos-rebuild boot` pasa a usar `--flake "$repo"`. El `?ref=` va antes del `#<perfil>`: con `#<perfil>?ref=<rama>`, Nix toma todo como nombre del atributo. En `createKeys`, la espera antes de `sudo reboot` baja de `sleep 10` a `sleep 5`. ⚠️ Paridad: `install-gpt-for-pc.sh` tiene un `echo ""` de más después del prompt de la rama, y la línea en blanco que lo sigue tiene espacios al final en todos los scripts menos `install-mbr.sh` (con `install-gpt.sh` da 20 líneas de diferencia en vez de 18). **README:** el paso 4 de VPS menciona el prompt de la rama. **Docs:** `AGENTS.md` §3 (Fase 3), §6.2, §6.7 (nueva), §7, P7 y §11.
- `206702a` — **Scripts (4):** corrige la instalación rota por `0198bc8`. En el bloque 2 (literal) del heredoc quedaban variables de bash que ya no se expandían: `users.users.$username` (error de Nix *"unexpected invalid token"* al instalar) pasa a `users.users.${username}`; `users = [ "$username" ];` del sudo sin contraseña (creaba la regla para un usuario llamado literalmente `$username`) pasa a `users = [ username ];`; y, en los scripts de PC, `device = "/dev/$diskName";` (GRUB en `/dev/$diskName`) pasa a `device = "/dev/${diskName}";`. Los tres usan ahora las variables del `let` del bloque 1. En `install-gpt.sh` también se quita el `{ config, lib, pkgs, ... }:` repetido al principio del bloque 2 (el módulo devolvía una función) y se agrega el `echo ""` que faltaba después del prompt de contraseña (paridad: vuelve a 18 líneas de diferencia con `install-mbr.sh`). **Docs:** `AGENTS.md` §0, §2, §5, §6.3, P7, §11 y §14 describen la estructura nueva de los heredocs; en este archivo se completan los hashes de `0198bc8` y `ecf131f`.

## 2026-11-10

- `0198bc8` — **Scripts:** ⚠️ además de lo que dice el mensaje, **mueve el límite entre los heredocs**: el bloque 1 queda solo con `{ config, lib, pkgs, ... }:` y el `let … in` (en PC, también `diskName`), y todo el attribute set pasa al bloque 2 (literal), con `$username`/`$diskName` sin expandir (instalación rota; corregido el 2026-11-11). En `install-gpt.sh` además queda repetido el encabezado del módulo. Resto del cambio: en los 4 scripts, nuevo prompt *"Type Nix Profile name"* (después de la contraseña del usuario, leído de `/dev/tty`, `nixos` si se deja vacío). El valor se interpola en el bloque 1 del heredoc como `let nixProfileName = "<perfil>"; in` antes del attribute set del `configuration.nix`, y `update` lo toma con interpolación de Nix (`nixProfileVar="${nixProfileName}"`, en el bloque 2) para construir `--flake "git+ssh://<url>#<perfil>"` en vez del `#nixos` fijo. `update` también muestra *"Perfil de Nix: …"*. **README** y **Docs** (`AGENTS.md` §0, §3, §5, §6.3, §6.4, §7, P7) actualizados.

## 2026-11-07

- `ecf131f` — **Docs:** revisión de seguridad de `AGENTS.md`: se agrega §10.3 (prueba real solo en una VM descartable, con disco virtual nuevo y sin discos ni carpetas del host), que se citaba pero faltaba; advertencias de "nunca en el host" en el `curl … | bash` de §1 y en los comandos del sistema instalado (§3 Fase 3 y tabla de §10.1); aclaración de que los arreglos de §9 son cambios al texto de los scripts; el `nix-build` de §10.2 copia al store solo los `install-*.sh` y ya no sugiere `nix-collect-garbage`; P10 actualizado por `b4f632f`.
- `b4f632f` — **README:** en "Comandos para PCs", el título de GPT pasa de *"(Opción 1)"* a *"(Opción 2)"* (corrige parte de P10).
- `5b3db9e` — **Docs:** ⚠️ el mensaje (en español) menciona solo `CHANGELOG.md` y `CLAUDE.md`, pero también agrega `AGENTS.md`. Se agregan `AGENTS.md` (contexto completo del proyecto para agentes y personas: flujo, mecánicas no obvias, convenciones, problemas conocidos P1–P10 y riesgos R1–R4, decisiones de diseño, checklist y la regla de que ninguna prueba de los scripts se ejecuta en el sistema principal: en el host solo se lee el texto, los chequeos estáticos van en el sandbox de Nix o en un contenedor sin red y la instalación en una VM descartable), este `CHANGELOG.md` (reconstruido a partir de los 70 commits) y `CLAUDE.md` (alias que importa `AGENTS.md` con `@AGENTS.md`).
- `a64e250` — **Scripts (4):** vuelve a agregar `clear` (con el comentario *"Clean the terminal before proceeding with user setup"*) justo después de `nixos-generate-config --root /mnt`, antes de los prompts de usuarios. Junto con `ab58750`, desde acá hay **dos** `clear`: uno al principio del script y otro antes de los prompts.
- `ab58750` — **Scripts (4):** ⚠️ el mensaje dice *"Remove duplicate terminal clear"*, pero no había duplicado: **mueve** el `clear` (y su comentario) de después de `nixos-generate-config` al principio del script, antes de `sudo -i` (corre como usuario `nixos`).

## 2026-11-06

- `aae049d` — **README:** títulos con *"(Opción 1)"*/*"(Opción 2)"*; "Próximos pasos" numerados **1.**–**4.**; "correr uno de estos comandos" → "optar por uno de estos comandos". En la sección de PCs las dos opciones quedaron como *"(Opción 1)"* (corregido en `b4f632f`).
- `23e3c77` — **Scripts (4):** `update` agrega un `echo ""` después de *"Actualizando con repo: …"*.
- `9e82d6c` — **Scripts (4):** `createKeys` ya no muestra *"Creating GitHub deploy key..."*; se desindenta la línea de `ssh-keygen`.
- `25f2528` — **Scripts (4):** `echo ""` después del prompt de la contraseña de root.
- `dd212b7` — **Scripts (4):** revierte `2315432` en `install-mbr.sh` (la salida de `parted`/`mkfs`/`mount`/`nixos-generate-config` vuelve a verse) y agrega `clear` después de `nixos-generate-config --root /mnt` en los 4 scripts.
- `2315432` — **Scripts (solo `install-mbr.sh`):** redirige a `/dev/null` la salida de `parted`, `mkfs.ext4`, `mkswap`, `mount`, `swapon` y `nixos-generate-config`. Revertido 3 minutos después en `dd212b7`.
- `7577d2c` — **Scripts (4):** en `createKeys`, `ssh-keygen` y el `tee` de `/root/.github_repo_url` pasan a `> /dev/null` (efecto colateral: si la clave ya existe, la pregunta de sobrescribir no se ve; R2).
- `3b8644c` — **Scripts (4):** se eliminan los alias `logs` (`cd /var/log`) y `disco` (`df -h`); queda solo `connect-repo = "createKeys"` con comentario. `PermitRootLogin` vuelve de `"yes"` a `"no"`. Reindentación del bloque `environment`.
- `183c8b6` — **Scripts (4):** se quitan `fail2ban` y `btop` de `environment.systemPackages` (queda `git`); comentarios *"You can delete this script"* sobre `createKeys` y `update`; se reindenta `update` a 2 espacios.
- `48217d6` — **Scripts (4):** comentarios nuevos (*"Configuration setup"*, *"Installation of NixOS and setting 'root' password"*, *"Setting the new user"*, *"Final messages"*) y typo *"installationr"*. En los scripts GPT unifica los mensajes finales con los de MBR (`echo ""` y *"REMOVE"*). Desde acá los 4 scripts quedan en **paridad total** (solo difieren en particionado y disco).
- `51995cb` — **README:** se quita la nota *"(No copiar este comando para Upcloud)"* del comando GPT.
- `4781917` — **README:** se quitan las notas *"Especialmente creado para máquinas virtuales."*.
- `c1d24eb` — **README:** títulos *"Comandos para servidores VPS"* y *"Comandos para PCs"*; se reemplaza `## Comandos:` por `---`.
- `bf0599e` — **README:** nueva descripción: *"Scripts para primera instalación de NixOS para servers VPS probados en Upcloud y para computadoras personales."*.
- `c2d37c5` — **README:** en PCs, *"Comando CURL para discos GPT (UEFI):"* → *"Para discos GPT (UEFI):"*.
- `58039dc` — **README:** separadores `---` entre opciones.
- `f363457` — **README:** títulos centrados con `<div align="center"><h3>…</h3></div>` (en vez de `style="text-align: center"`, que GitHub ignora).
- `a7acead` — **README:** títulos de sección en `<h3>` centrados, `<br>` entre VPS y PCs, *"¡Este es el correcto para VPS Upcloud!"*.
- `da0cb9b` — **Scripts:** nuevos `install-mbr-for-pc.sh` e `install-gpt-for-pc.sh`, copias de los de VPS que piden el nombre del disco (`diskName`, con ayuda para `lsblk`), usan `/dev/$diskName` y `/dev/$diskName"N"`, swap de **2 GB** y `boot.loader.grub.device = "/dev/$diskName"`. **README:** secciones "Para servidores VPS" y "Para PCs", subtítulo "Próximos pasos".
- `df15c51` — **README:** el comando `ssh` agrega `-o UserKnownHostsFile=/tmp/known_hosts_tmp`.
- `cdee6e6` — **README:** ⚠️ el mensaje dice *"remove StrictHostKeyChecking"*, pero **agrega** `-o StrictHostKeyChecking=no` al comando `ssh`.
- `8209419` — **Scripts (VPS):** el prompt de la contraseña del usuario pasa a *"Type new password for '$username': "*.
- `c3cb08a` — **Scripts (VPS):** ⚠️ el mensaje dice *"Add clean on reboot"*, pero `tmp.cleanOnBoot` existía desde `b4280ea`. Lo que hace es **dividir el heredoc en dos**: el bloque 1 (`<< EOF`, interpolado) termina después de `security`, y el bloque 2 (`tee -a … << 'EOF'`, literal) contiene `systemPackages`, `createKeys`, `update`, alias, OpenSSH, firewall y `stateVersion`. Arregla la rotura de `a9f0198`. En `install-gpt.sh` además elimina el alias `update` viejo (`bash -c`, con `switch`) que tapaba al binario `update`, y los alias `createDeployKeys`/`connectRepo`.
- `a9f0198` — **Scripts (VPS):** ⚠️ el mensaje dice *"for consistency"*: quita las comillas del delimitador (`<< 'EOF'` → `<< EOF`) para que `$username` se expanda. Efecto colateral: también se expandían al instalar `$repoUrl`, `$(tr …)`, `$repoParsed` y `$repo_url` del código de `createKeys`/`update`, que quedaban vacíos o rotos. Corregido en `c3cb08a`.
- `b83b24e` — **Scripts (VPS):** los prompts de usuarios pasan **antes** del heredoc y `nixi` se reemplaza por `$username` en `users.users` y en `security.sudo.extraRules`. Como el heredoc todavía tenía comillas, quedaba `users.users.$username` literal (Nix inválido) hasta `a9f0198`.
- `44a96f9` — **README:** explica que el script pide usuario y clave; `ssh [nombre de usuario creado]@[IP del servidor]`. El paso de `connect-repo` siguió diciendo *"con usuario 'nixi'"* (P10).
- `fdf1bc5` — **Scripts (VPS):** pide el nombre del nuevo usuario (`username`) y su contraseña, junto con la de root, antes de instalar (todavía después del heredoc); `chpasswd` usa `$username`. Mensajes *"Password for root is saved!"*, *"All users are set!"*, *"Now installing NixOS..."*, *"REMOVE the installation media"*. El `configuration.nix` seguía con `nixi` fijo.

## 2026-11-05

- `91f9495` — **Scripts (VPS):** el mensaje de `createKeys` termina en `:` (*"…como deploy key:"*).
- `30cab0b` — **Scripts (VPS):** reemplaza el heredoc anidado de `/root/.ssh/config` por `echo -e "Host github.com\n  HostName …" | sudo tee /root/.ssh/config > /dev/null`. Arregla `da9847c`.
- `51ae9b4` — **README:** MBR primero con *"(Este es el correcto para VPS Upcloud)"*, GPT con *"(No copiar este comando para Upcloud)"*; pasos `ssh nixi@[IP del servidor]` y `connect-repo`.
- `77cab70` — **Scripts (VPS):** `update` usa `nixos-rebuild boot` en vez de `switch` (la nueva configuración se aplica al reiniciar).
- `a94624e` — **Scripts (VPS):** líneas en blanco (`echo ""`) alrededor de los mensajes de `createKeys`.
- `da9847c` — **Scripts (VPS):** refactor grande de `createKeys`/`update`:
  - `update` pasa de alias (`bash -c '…'`) a `writeShellScriptBin "update"` (lee la URL con `sudo cat`, sin `&&` entre comandos) y `createKeys` lo llama directamente.
  - La URL se convierte con `tr ':' '/'` (formato scp → `git+ssh://`) y se guarda con `sudo tee /root/.github_repo_url`; mensaje *"Repositorio se guardó correctamente: $repoParsed"*; `sleep 5` → `sleep 10`.
  - En `install-mbr.sh` se quitan los alias `createDeployKeys` y `connectRepo`; `install-gpt.sh` los conservó, junto con el alias `update` viejo, hasta `c3cb08a`.
  - ⚠️ Bug introducido: el `/root/.ssh/config` se escribe con un heredoc anidado cuyo `EOF` está en la columna 0, lo que **cierra el heredoc externo** del `configuration.nix`. El resto del código de `createKeys` se ejecutaba en el ISO al instalar. Corregido en `30cab0b`.
- `769a995` — **Scripts (VPS):** quita comentarios sueltos del `configuration.nix` (*"Use the GRUB 2 boot loader"*, *"Security tools"*, *"System utilities"*, *"Enable the OpenSSH daemon"*).
- `5366e24` — **Scripts (VPS):** quita más comentarios por defecto (red, zona horaria, cuenta de usuario).
- `262276f` — **Scripts (VPS):** elimina el bloque de comentarios por defecto de `nixos-generate-config` del `configuration.nix`; agrega `security.sudo.extraRules` (`nixi` puede ejecutar `ALL` con `NOPASSWD`); `createKeys` vuelve a usar `sudo` en `tee`, `ssh-keygen` y `cat`.
- `79f5759` — **Scripts (VPS):** quita los `sudo` de `createKeys` (revertido en `262276f`); reemplaza la llamada a `update` dentro de `createKeys` por un `bash -c '…'` equivalente (con `switch`); simplifica el alias `update` (sin chequeos de archivo vacío o inexistente). En `install-gpt.sh` el cambio quedó parcial.
- `c22a15f` — **Scripts (VPS):** `createKeys` deja de usar `sudo -i` (no eleva las líneas siguientes de un script) y pasa a `sudo` por comando (`tee`, `ssh-keygen`, `cat`).
- `ae8759d` — **Scripts (VPS):** la contraseña de `nixi` se pone con `echo "nixi:$password" | chpasswd -R /mnt` (el intento con `nixos-enter` queda comentado).
- `cd0fa53` — **Scripts (solo `install-gpt.sh`):** línea en blanco antes de los mensajes finales.
- `b4d06e7` — **Scripts (VPS):** mensajes *"Password for root set!"* e *"Installing NixOS..."*; prueba `nixos-enter --root /mnt` seguido de `echo "$password" | passwd nixi` (no funciona: `nixos-enter` abre un shell interactivo).
- `7fb73bd` — **Scripts (VPS):** los prompts de contraseña pasan a `read -rp "…" var < /dev/tty` porque stdin es el script. Se pierde el `-s`: desde acá las contraseñas se ven en pantalla (P4).
- `da5a8f7` — **Scripts (VPS):** prompts con `read -srp "Type new password: " …` (ocultos).
- `d79b50f` — **Scripts (VPS):** `echo ""` antes del prompt de root.
- `0736a30` — **Scripts (VPS):** pide la contraseña de root (`read -s passwordRoot`) y la pasa con `echo "$passwordRoot" | nixos-install`. No tiene efecto: `nixos-install` solo pide la contraseña si stdin es una terminal (P1). La de `nixi` pasa a `echo "$password" | nixos-enter --root /mnt -c 'passwd nixi'`.
- `a8cdcd7` — **Scripts (VPS):** revierte el `echo "…"` de `4fa0101` y vuelve al heredoc (`tee … > /dev/null << 'EOF'`); la contraseña de `nixi` vuelve a `nixos-enter --root /mnt -c 'passwd nixi'` interactivo.
- `e662bd9` — **Scripts (VPS):** la contraseña de `nixi` se lee con `read -s` y se pasa por pipe a `nixos-enter … passwd nixi`.
- `4fa0101` — **Scripts (VPS):**
  - El `configuration.nix` se escribe con `echo "…" > /mnt/etc/nixos/configuration.nix` en vez de heredoc (frágil: el contenido tiene comillas dobles; revertido en `a8cdcd7`).
  - `PermitRootLogin = "yes"`.
  - En `install-gpt.sh` reemplaza `systemd-boot` + `efi.canTouchEfiVariables` por `loader.grub` con `device = "/dev/vda"`. Es el **origen de P2**: GPT sin bootloader UEFI.
- `6aef331` — **Scripts (VPS):** en el alias `update`, `${repo_url}` → `$repo_url` (dentro de un string `''…''` de Nix, `${…}` es interpolación de Nix y hacía fallar la evaluación).
- `fc67a35` — **Scripts (VPS):** reindenta `createKeys`; en `install-mbr.sh` reemplaza el heredoc de `/root/.github_repo_url` por `echo "$repoUrl" > /root/.github_repo_url` (en `install-gpt.sh` ya se había hecho en `db79410`).
- `db79410` — **Scripts (solo `install-gpt.sh`):** `echo "$repoUrl" > /root/.github_repo_url` en vez de heredoc; líneas en blanco.
- `23ade5f` — **README:** *"Primera instalación de NixOS para servers VPS. Probado en servers Upcloud."*.
- `a2d6a6b` — **README:** mayúscula corregida (*"Para"* → *"para"*).
- `abb1957` — **README:** descripción traducida al español.
- `14873e2` — **README:** sección "Comandos" con los `curl` para GPT (UEFI) y MBR (BIOS).
- `f62b2d8` — **Scripts (VPS):** shebang `#!/bin/bash` → `#!/usr/bin/env bash`.
- `6d2bf39` — **Scripts (VPS):** `ssh-keygen … -N ""` (deploy key sin passphrase, para que root pueda clonar sin intervención).
- `daac08f` — **Scripts:** `install-gpt.sh` completo:
  - Tabla GPT en `/dev/vda`: root ext4 `512MB`→`-1GB`, swap `-1GB`→`100%`, ESP FAT32 `1MB`→`512MB` (partición 3, flag `esp`, montada en `/mnt/boot`).
  - Bootloader `systemd-boot` + `efi.canTouchEfiVariables`.
  - El resto, igual que `install-mbr.sh` en ese momento (`createKeys`, alias `update`, etc.).
- `053cca4` — **Scripts (`install-mbr.sh`):** `createKeys` reinicia al terminar (*"Reiniciando sistema..."*, `sleep 5`, `sudo reboot`).
- `080c283` — **Scripts (`install-mbr.sh`):** `createKeys` ejecuta `update` automáticamente; el alias `update` usa `sudo` en `nixos-generate-config` y `nixos-rebuild`; nuevos alias `createDeployKeys`, `connectRepo` y `connect-repo` → `createKeys`. Queda comentado un `update` con la URL fija `git+ssh://git@github.com/mjb10/nixos-server`.
- `8151be1` — **Scripts (`install-mbr.sh`):** mensajes *"Repositorio se guardó correctamente."* e indicación de ejecutar `update`; `exit 0`.
- `a2b7486` — **Scripts (`install-mbr.sh`):** descomenta el substituter `https://nix-community.cachix.org` (sin su clave pública: P3).
- `904fd62` — **Scripts (`install-mbr.sh`):** mensaje *"Usando repo dinámico"* → *"Actualizando con repo"*.
- `e479142` — **Scripts (`install-mbr.sh`):** líneas en blanco en `createKeys`.
- `93526f5` — **Scripts (`install-mbr.sh`):** primera versión de la conexión al repo del flake:
  - `createKeys` (`writeShellScriptBin`): `sudo -i`, heredoc para `/root/.ssh/config` (`Host github.com`, deploy key, `StrictHostKeyChecking accept-new`), `ssh-keygen -t ed25519 -f /root/.ssh/github_deploy_key`, muestra la clave pública, pide la URL y la guarda en `/root/.github_repo_url`.
  - Alias `update` (`bash -c`): valida que exista el archivo y ejecuta `nixos-generate-config && nixos-rebuild switch --flake "git+ssh://${repo_url}#nixos" --refresh --impure --no-write-lock-file -I hardware=/etc/nixos/hardware-configuration.nix`.
  - Alias `logs` y `disco`.
  - En comentarios queda la versión anterior con la URL fija `git@github.com/mjb10/nixos-server`.
- `06e0117` — **Scripts:** swap de `install-mbr.sh` de 4 GB a **1 GB** (`-4GB` → `-1GB`); se crea `install-gpt.sh` vacío (solo shebang). **README:** *"First install NixOS system for VPS servers"*.
- `b4280ea` — **Scripts:** primer `install-mbr.sh`:
  - `sudo -i`; MBR en `/dev/vda` con root `1MB`→`-4GB` (flag `boot`) y swap de 4 GB; ext4 `nixos` y swap `swap`; `nixos-generate-config --root /mnt`.
  - `configuration.nix` completo con `tee … << 'EOF'`: GRUB en `/dev/vda`, `linuxPackages_latest`, `tmp.cleanOnBoot`, flakes, `cache.nixos.org`, NetworkManager, zona horaria de Buenos Aires, usuario fijo `nixi` (`wheel`, `docker`, `tree`), `fail2ban`/`git`/`btop`, OpenSSH sin root con contraseña y `AllowGroups = [ "wheel" ]`, firewall apagado, `stateVersion = "26.11"`, con todos los comentarios por defecto.
  - `nixos-install`, `nixos-enter --root /mnt -c 'passwd nixi'` y `poweroff`.
- `d350d15` — **README:** commit inicial, solo el título `# nixos-first-install`.
