# AGENTS.md — nixos-first-install

> Contexto completo para agentes de IA (Claude, Codex, Gemini, Copilot, etc.) y para cualquier persona que retome el proyecto.
> `CLAUDE.md` es solo un alias que importa este archivo: **editá siempre `AGENTS.md`**, nunca `CLAUDE.md`.
> Historial detallado commit por commit: [`CHANGELOG.md`](CHANGELOG.md) (lo más nuevo arriba).
> Revisado el **2026-11-07** contra el commit **`b4f632f`** (último de `main` a esa fecha; los scripts no cambian desde `a64e250`). Si `git log -1` muestra otro commit, revisá lo que cambió después (`git log b4f632f..HEAD -p`) antes de confiar ciegamente en este documento.

---

## 0. Lo mínimo antes de tocar algo

1. **Nunca ejecutes ni pruebes nada de los `install-*.sh` en el sistema principal** (la máquina donde está clonado el repo): borran y reparticionan un disco sin pedir confirmación. En el host solo se **lee** el texto; los chequeos estáticos van en el sandbox de Nix o en un contenedor sin red, y la instalación en una VM descartable (§10).
2. **Paridad:** los 4 scripts son copias; todo cambio común va en los 4 (§8).
3. **Dos heredocs:** lo que se interpola al instalar (`$username`, `$diskName`, `$nixProfile`) va en el bloque 1; el código de `createKeys`/`update` va en el bloque 2, literal (§6.3).
4. **Todo `read` usa `< /dev/tty`**: el script llega por stdin (`curl … | bash`), así que stdin *es* el script (§6.1, §6.2).
5. **`main` es producción:** cada push lo descarga el próximo que ejecute el `curl`. Documentá todo cambio en `CHANGELOG.md` (y en `README.md`/`AGENTS.md` si corresponde) (§13, §14).

---

## 1. Resumen rápido

- **Qué es:** 4 scripts Bash que hacen la *primera instalación* de NixOS desde el ISO live: particionan y formatean un disco, generan un `configuration.nix` mínimo, ejecutan `nixos-install` y apagan la máquina.
- **Para qué:** dejar un sistema base al que se entra por SSH y que, con un solo comando (`connect-repo`), pasa a gestionarse desde **otro repositorio con un flake de NixOS** (externo a este repo, ver §7).
- **Dónde se usa:** VPS (probado en **Upcloud** con `install-mbr.sh`) y PCs.
- **Cómo se ejecuta:** solo desde el ISO live de NixOS, en la máquina que se va a borrar: `curl -sSL https://raw.githubusercontent.com/mjb10/nixos-first-install/refs/heads/main/<script>.sh | bash`. ⚠️ Borra el disco sin preguntar: nunca en el host ni en una máquina con datos (§10).
- **Estado:** solo `install-mbr.sh` está confirmado como funcional (Upcloud). Los scripts GPT casi seguro no arrancan (P2). Hay 10 problemas conocidos sin corregir (§9).
- **No hay** build, tests automáticos, CI, releases, tags, licencia, `.gitignore` ni `flake.nix` (este repo **no** es un flake; el flake vive en otro repo).
- **Idiomas:** README y documentación en español (rioplatense). Mensajes del instalador en inglés; mensajes de `createKeys`/`update` en español. Comentarios del código en inglés. Commits en inglés.
- **Dueño:** usuario de GitHub `mjb10`. Remoto: `https://github.com/mjb10/nixos-first-install.git`. Única rama: `main`.

---

## 2. Archivos del repositorio

Estructura plana, sin subdirectorios.

### Scripts de instalación

| Archivo | Destino | Tabla de particiones | Firmware previsto | Disco | Swap |
|---|---|---|---|---|---|
| `install-mbr.sh` | VPS | MBR (`msdos`) | BIOS | `/dev/vda` (fijo) | 1 GB |
| `install-gpt.sh` | VPS | GPT | UEFI (⚠️ ver P2) | `/dev/vda` (fijo) | 1 GB |
| `install-mbr-for-pc.sh` | PC | MBR (`msdos`) | BIOS | se pregunta (`diskName`) | 2 GB |
| `install-gpt-for-pc.sh` | PC | GPT | UEFI (⚠️ ver P2) | se pregunta (`diskName`) | 2 GB |

Los 4 scripts son **casi idénticos** (copias). Solo difieren en:

1. **Particionado/formateo/montaje** (MBR vs GPT, §4).
2. **VPS vs PC:** los de PC piden el nombre del disco (justo después de `sudo -i`, o sea que responde root) y usan `/dev/$diskName`, `/dev/$diskName"1"`, etc. (incluido `boot.loader.grub.device = "/dev/$diskName"`); la swap es de 2 GB en vez de 1 GB.
3. Diferencias cosméticas de espacios: en los de VPS, `-N ""  > /dev/null` y `tee /root/.github_repo_url  > /dev/null` llevan doble espacio.

Todo lo demás (prompts, `configuration.nix`, `createKeys`, `update`, cierre) es igual y **debe mantenerse igual** (§8).

### Documentación

- `README.md` — instrucciones para el usuario final (en español). Tiene errores conocidos (P10).
- `AGENTS.md` — este archivo.
- `CHANGELOG.md` — historial de cambios, lo más nuevo arriba (§13).
- `CLAUDE.md` — alias: solo importa `AGENTS.md` con la sintaxis `@AGENTS.md` de Claude Code.

---

## 3. Flujo completo, de punta a punta

### Fase 1 — Instalación (en el ISO live de NixOS)

El ISO minimal de NixOS inicia sesión solo como el usuario `nixos`, que tiene `sudo` sin contraseña. El usuario ejecuta el `curl … | bash` del README.

1. `clear` → limpia la pantalla (todavía como usuario `nixos`).
2. `sudo -i` → el resto del script corre como root (§6.1 explica por qué funciona y por qué depende del pipe).
3. **Solo PC:** pide el nombre del disco (`vda`, `sda`, …) → variable `diskName`.
4. Particiona con `parted`, formatea, monta en `/mnt` y activa la swap (§4). La salida de estos comandos queda visible a propósito.
5. `nixos-generate-config --root /mnt` → crea `hardware-configuration.nix` y un `configuration.nix` por defecto.
6. `clear` y pide, leyendo de `/dev/tty`: contraseña de root (`passwordRoot`), nombre del nuevo usuario (`username`), su contraseña (`password`) y el nombre del perfil de Nix (`nixProfile`, `nixos` si se deja vacío): el nombre de la configuración del flake que va a construir `update` (`nixosConfigurations.<perfil>`, §7). Se ven en pantalla (P4).
7. **Sobrescribe** `/mnt/etc/nixos/configuration.nix` con dos heredocs (§5 y §6.3).
8. `echo "$passwordRoot" | nixos-install` → instala. ⚠️ La contraseña de root **no** se aplica (P1).
9. `echo "$username:$password" | chpasswd -R /mnt` → contraseña del nuevo usuario.
10. Mensajes finales (*"Don't forget to REMOVE the installation media…"*), `sleep 5` y `poweroff`.

### Fase 2 — Primer arranque

El usuario retira el CD/DVD/ISO, enciende la máquina y entra por SSH con el usuario creado:

```bash
ssh -o UserKnownHostsFile=/tmp/known_hosts_tmp -o StrictHostKeyChecking=no <usuario>@<IP>
```

Esas opciones evitan el error de *host key* cambiada al reinstalar un VPS con la misma IP y no ensucian `~/.ssh/known_hosts`.

### Fase 3 — Conexión al repo del flake (`connect-repo`)

> ⚠️ Todo lo de esta fase corre **en el sistema recién instalado** (el VPS o la PC nueva), nunca en el host. Ahí `sudo nixos-generate-config` sobrescribe `/etc/nixos/hardware-configuration.nix`, `sudo nixos-rebuild boot …` cambia la configuración con la que arranca la máquina y `createKeys` pisa `/root/.ssh/config` y reinicia. Los comandos de abajo describen el código: no son para copiar y ejecutar.

`connect-repo` es un alias de shell (`environment.shellAliases`) que ejecuta el comando `createKeys`. Los alias solo existen en shells interactivos: en un comando no interactivo (p. ej. `ssh host comando`) hay que llamar a `createKeys` directamente.

`createKeys`:

1. Escribe `/root/.ssh/config` con `echo -e … | sudo tee`: `Host github.com`, `HostName github.com`, `User git`, `IdentityFile /root/.ssh/github_deploy_key`, `IdentitiesOnly yes`, `StrictHostKeyChecking accept-new` (ver R1).
2. Genera `/root/.ssh/github_deploy_key` (ed25519, sin passphrase: `-N ""`; salida a `/dev/null`, ver R2).
3. Muestra la clave pública. El usuario la agrega en GitHub como **Deploy key** del repo del flake (con permiso de lectura alcanza).
4. Pide la URL SSH del repo (`read repoUrl`; acá sí es interactivo, no hace falta `/dev/tty`) con formato scp: `git@github.com:usuario/repo.git`. Reemplaza **todos** los `:` por `/` (`tr ':' '/'`) → `git@github.com/usuario/repo.git` y la guarda en `/root/.github_repo_url`.
5. Ejecuta `update`:
   - Lee `/root/.github_repo_url` (con `sudo cat … | xargs`, que recorta espacios y saltos de línea).
   - `sudo nixos-generate-config` → regenera `/etc/nixos/hardware-configuration.nix` (no pisa `configuration.nix` porque ya existe).
   - `sudo nixos-rebuild boot --flake "git+ssh://<url>#<perfil>" --refresh --impure --no-write-lock-file -I hardware=/etc/nixos/hardware-configuration.nix`
6. `sleep 10` y `sudo reboot` → arranca la generación construida desde el flake.

Después, `update` queda disponible para volver a sincronizar con el repo (mientras el flake siga incluyendo estos scripts; el propio código dice *"You can delete this script"*).

---

## 4. Esquema de particiones

| Script | Partición 1 | Partición 2 | Partición 3 |
|---|---|---|---|
| `install-mbr.sh` | root ext4, etiqueta `nixos`, `1MB` → `-1GB`, flag `boot` | swap, etiqueta `swap`, `-1GB` → `100%` | — |
| `install-mbr-for-pc.sh` | igual, hasta `-2GB` | swap `-2GB` → `100%` | — |
| `install-gpt.sh` | root ext4 `nixos`, `512MB` → `-1GB` | swap `swap`, `-1GB` → `100%` | ESP FAT32, etiqueta `boot`, `1MB` → `512MB`, flag `esp`, montada en `/mnt/boot` |
| `install-gpt-for-pc.sh` | igual, hasta `-2GB` | swap `-2GB` → `100%` | igual |

- En GPT la ESP es la **partición 3** aunque físicamente esté al principio del disco, porque se crea última. Los `mkfs`/`mount` dependen de esa numeración.
- Dispositivos: VPS usa `/dev/vda1..3`; PC usa `/dev/$diskName"1"..` (no sirve para NVMe/eMMC, P6).
- `parted` se invoca sin `-s` (modo script) y `mkfs` sin `-F` (ver R3).

---

## 5. `configuration.nix` que genera el instalador

Resultado (igual en los 4 scripts salvo `boot.loader.grub.device`):

- `let nixProfileName = "<perfil>"; in` antes del attribute set: el nombre de perfil ingresado al instalar, que `update` usa como `#<perfil>` (§6.4).
- `imports = [ ./hardware-configuration.nix ];`
- `boot.loader.grub = { enable = true; device = "/dev/vda"; }` (PC: `"/dev/$diskName"`). **También en los scripts GPT** (P2).
- `boot.kernelPackages = pkgs.linuxPackages_latest;`
- `boot.tmp.cleanOnBoot = true;`
- `nix.settings`: `experimental-features = [ "nix-command" "flakes" ]`, `max-jobs = "auto"`, `substituters = [ cache.nixos.org, nix-community.cachix.org ]` (P3).
- `networking.hostName = "nixos";`, `networking.networkmanager.enable = true;`
- `time.timeZone = "America/Argentina/Buenos_Aires";`
- `users.users.<username>`: `isNormalUser = true`, `extraGroups = [ "wheel" "docker" ]` (P9), `packages = [ tree ]`.
- `security.sudo.extraRules`: `<username>` puede ejecutar `ALL` con `NOPASSWD`.
- `environment.systemPackages`: `git`, `createKeys` y `update` (ambos `writeShellScriptBin`).
- `environment.shellAliases.connect-repo = "createKeys";`
- `services.openssh`: `enable = true`, `PermitRootLogin = "no"`, `PasswordAuthentication = true`, `AllowGroups = [ "wheel" ]`.
- `networking.firewall.enable = false;`
- `system.stateVersion = "26.11";` (fijo; ver R4).

Es una configuración **deliberadamente permisiva y transitoria** (firewall apagado, login por contraseña, sudo sin contraseña): su único objetivo es permitir el primer acceso por SSH y el `connect-repo`. El endurecimiento le corresponde al flake externo.

---

## 6. Mecánicas no obvias (leer antes de tocar los scripts)

### 6.1 `sudo -i` funciona solo porque el script llega por stdin

Con `curl … | bash`, bash lee el script desde el pipe línea por línea. Al ejecutar `sudo -i`, se abre un shell de login de root que **hereda ese mismo stdin** y se pone a leer y ejecutar **el resto del script** como root. Cuando termina, el bash original recibe EOF y sale.

Consecuencias:

- El script debe recibirse por stdin: `curl … | bash` o, con una copia local **dentro de la VM de prueba**, `cat script.sh | bash`. Nunca en el sistema principal (§10).
- `bash script.sh` **no** sirve: `sudo -i` abre un shell root interactivo, y el resto del script corre recién al salir de él, como el usuario `nixos` (sin permisos).
- Lo que está **antes** de `sudo -i` (hoy, solo el primer `clear`) corre como `nixos`.
- No agregues comandos que lean stdin (ver 6.2).

### 6.2 Toda entrada del usuario se lee de `/dev/tty`

Como stdin es el propio script, un `read` normal se "comería" las líneas siguientes del script. Por eso todos los prompts usan `read -rp "…" variable < /dev/tty`. Cualquier prompt nuevo **debe** hacer lo mismo. Lo mismo aplica a cualquier comando que pueda pedir confirmación interactiva (R3). Esto rige solo para el instalador: `createKeys` corre en una sesión SSH interactiva y usa `read` normal.

### 6.3 El `configuration.nix` se escribe con DOS heredocs

```bash
tee /mnt/etc/nixos/configuration.nix > /dev/null << EOF      # bloque 1: SIN comillas
  …abre `{`, imports, boot, nix.settings, red, usuario, sudo…
EOF

tee -a /mnt/etc/nixos/configuration.nix << 'EOF' >/dev/null  # bloque 2: CON comillas, append
  …systemPackages (createKeys, update), alias, openssh, firewall, stateVersion y cierra `}`…
EOF
```

- **Bloque 1 (`<< EOF`, sin comillas):** bash expande variables al instalar. Por eso ahí van `$username`, `$diskName` y `$nixProfile`. Cualquier `$`, `$(…)` o comilla invertida también se expandiría: para un `$` literal usá `\$`.
- **Bloque 2 (`<< 'EOF'`, con comillas):** se copia literal. Ahí va el código shell de `createKeys`/`update`, que usa `$repoUrl`, `$(tr …)`, etc. y debe llegar intacto al archivo Nix para ejecutarse **en tiempo de uso**, no al instalar.
- El attribute set de Nix **se abre en el bloque 1 y se cierra en el bloque 2** (la `}` final). Si movés código entre bloques, mantené las llaves balanceadas.
- **Ninguna línea del contenido puede ser exactamente `EOF`:** cerraría el heredoc antes de tiempo, y todo lo que sigue se ejecutaría **como comandos de shell en el ISO, como root**. Pasó en `da9847c` (heredoc anidado para `/root/.ssh/config`, cuyo código siguiente incluía `sudo reboot`) y se arregló en `30cab0b` con `echo -e "…\n…" | sudo tee`.
- Antes de `c3cb08a` todo estaba en un único heredoc; en `a9f0198` se le sacaron las comillas para interpolar `$username`, lo que rompía el código de `createKeys` (se ejecutaba `$(tr …)` al instalar). La división en dos bloques es la solución: **no la deshagas**.

### 6.4 Strings `''…''` de Nix dentro de `writeShellScriptBin`

`createKeys` y `update` son strings multilínea de Nix (`'' … ''`). Dentro de ellos `${…}` es **interpolación de Nix**, no de bash: `${repo_url}` hacía fallar la evaluación (arreglado en `6aef331` usando `$repo_url`). Usá `$var` sin llaves o escapalo como `''${var}`. Para escribir `''` literal se usa `'''`. Excepción intencional: `update` usa `${nixProfileName}` para leer la variable del `let` del bloque 1 (la interpola Nix al construir el sistema) y la guarda en la variable de bash `nixProfileVar`.

### 6.5 `nixos-rebuild boot` + `reboot` (no `switch`)

`update` construye la nueva generación y la deja como predeterminada para el próximo arranque; `createKeys` reinicia después. Se cambió de `switch` a `boot` en `77cab70`: el cambio de configuración (red, SSH, usuarios) se aplica en un arranque limpio en vez de en caliente sobre la sesión SSH activa.

### 6.6 `sudo` por comando dentro de `createKeys`/`update`

El usuario entra por SSH sin privilegios, así que cada comando que toca `/root` o el sistema lleva su propio `sudo` (sudo sin contraseña por `extraRules`). Un `sudo -i` dentro de un script **no** eleva las líneas siguientes (se probó y se descartó en `c22a15f`).

---

## 7. Contrato con el repositorio externo del flake

Este repo **no** contiene la configuración final; `update` la trae de otro repo. Ese repo debe cumplir con:

1. Ser un flake en la raíz, accesible por SSH en GitHub con la deploy key generada (`Host github.com` está fijo en `/root/.ssh/config`).
2. Exponer **`nixosConfigurations.<perfil>`**, donde `<perfil>` es el nombre de perfil de Nix ingresado al instalar (`nixos` por defecto; queda fijo en `update` vía `nixProfileName`).
3. Tolerar `--impure`: se evalúa con `-I hardware=/etc/nixos/hardware-configuration.nix`, así que puede importar el hardware con `<hardware>` o con la ruta absoluta `/etc/nixos/hardware-configuration.nix`.
4. `--no-write-lock-file` y `--refresh`: siempre toma el último commit de la rama por defecto y no escribe `flake.lock` (que conviene tener commiteado en ese repo).
5. Definir el bootloader correcto para el disco (p. ej. GRUB en `/dev/vda` en Upcloud), el usuario creado (con `wheel` y sudo, o `update` dejará de funcionar) y el endurecimiento de seguridad.
6. Si usa `users.mutableUsers = false`, las contraseñas puestas por el instalador con `chpasswd` se pierden: tiene que declararlas (`hashedPassword`, etc.).
7. Si no incluye `createKeys`/`update`, esos comandos desaparecen tras el primer reinicio. Si copia su código, tiene que definir `nixProfileName` (o reemplazar `${nixProfileName}` por el nombre del perfil): sin eso, la evaluación falla.

Referencia: el historial (`93526f5`, `080c283`) muestra que el repo del autor para servidores es `git@github.com:mjb10/nixos-server` (probablemente privado; no está en este repo).

---

## 8. Convenciones y reglas de trabajo

### Paridad entre los 4 scripts (la regla más importante)

- Todo cambio que no sea específico de MBR/GPT o de VPS/PC se aplica **en los 4 scripts**.
- Para verificar la paridad después de editar (`diff` solo compara texto y no ejecuta nada de los scripts: es de lo poco que se puede correr en el host, §10.1):
  ```bash
  diff install-mbr.sh install-gpt.sh                # solo debe diferir el particionado
  diff install-mbr.sh install-mbr-for-pc.sh         # solo diskName, tamaños de swap y espacios
  diff install-gpt.sh install-gpt-for-pc.sh         # ídem
  diff install-mbr-for-pc.sh install-gpt-for-pc.sh  # solo el particionado
  ```
  Referencia al `a64e250`: `diff install-mbr.sh install-gpt.sh | grep -c '^[<>]'` da **18** líneas. Si da más, se rompió la paridad.
- Si una diferencia nueva es intencional, documentala en §2.
- La paridad ya se perdió antes: entre `da9847c` y `c3cb08a`, `install-gpt.sh` conservó un alias `update` viejo (con `switch`) que tapaba al binario `update`.

### Estilo

- Shebang `#!/usr/bin/env bash` (desde `f62b2d8`).
- Prompts: `read -rp "Texto: " variable < /dev/tty`, con `echo ""` para separar bloques.
- Mensajes del instalador en **inglés**; mensajes de `createKeys`/`update` en **español**; README en **español rioplatense**.
- Nix con indentación de 2 espacios; comentarios en inglés.
- La salida de `parted`/`mkfs`/`mount` se deja **visible** a propósito (se ocultó en `2315432` y se revirtió en `dd212b7`).
- El `configuration.nix` generado se mantiene **mínimo**: paquetes y alias extra (`fail2ban`, `btop`, `logs`, `disco`) se quitaron a propósito (`183c8b6`, `3b8644c`); lo extra va en el flake.

### Git

- Commits en inglés, en imperativo y con mayúscula inicial (`Add …`, `Fix …`, `Refactor …`, `Remove …`, `Update …`). Sin Conventional Commits.
- Se trabaja directo sobre `main`, que es lo que se descarga. Para cambios no triviales, conviene usar una rama y probarla en una VM con la URL raw de esa rama (`…/refs/heads/<rama>/<script>.sh`) antes de mergear.
- **Varios mensajes de commit no coinciden con su diff.** Para entender la historia, leé los diffs o `CHANGELOG.md`, no solo los mensajes. Los casos más engañosos:
  - `cdee6e6` dice *remove StrictHostKeyChecking* pero lo **agrega** al comando `ssh` del README.
  - `c3cb08a` dice *Add clean on reboot* pero `tmp.cleanOnBoot` existía desde el primer script; lo que hace es **dividir el heredoc** en dos.
  - `a9f0198` dice *for consistency* pero cambia la semántica: habilita la interpolación en el heredoc (y rompe `createKeys` hasta `c3cb08a`).
  - `ab58750` dice *Remove duplicate terminal clear* pero **mueve** el `clear` al principio del script; `a64e250` vuelve a agregar otro antes de los prompts, así que hoy hay dos.

### Documentación

- Todo cambio va en `CHANGELOG.md`, **arriba de todo** (§13).
- Si cambia algo visible para el usuario, actualizá `README.md`.
- Si cambia la estructura, el flujo o un problema conocido, actualizá este archivo (incluida la línea "Revisado el … contra el commit …" del encabezado).

---

## 9. Problemas conocidos

Detectados leyendo el código al 2026-11-07 (`a64e250`). **No están corregidos.** No los arregles sin que el usuario lo pida, pero tenelos en cuenta (y, si corregís uno, sacalo de esta tabla y anotalo en `CHANGELOG.md`). Los arreglos sugeridos (acá y en los riesgos) son cambios **al texto de los scripts**, no comandos para ejecutar en el host.

| ID | Problema | Dónde | Detalle / arreglo sugerido |
|---|---|---|---|
| P1 | **La contraseña de root nunca se establece** | 4 scripts, `echo "$passwordRoot" \| nixos-install` | `nixos-install` solo pide la contraseña de root si stdin es una terminal (`if [[ -z $noRootPasswd ]] && [ -t 0 ]`, verificado en el código de `nixos-install`). Con un pipe se saltea ese paso y root queda sin contraseña (bloqueado). El acceso funciona igual por el usuario con sudo. Arreglo: `nixos-install --no-root-passwd` y después `echo "root:$passwordRoot" \| chpasswd -R /mnt`. |
| P2 | **Los scripts GPT instalan GRUB en modo BIOS** | `install-gpt.sh`, `install-gpt-for-pc.sh` | `boot.loader.grub.device = "/dev/…"` sin `efiSupport` en un disco GPT sin partición `bios_grub`: casi con seguridad `grub-install` falla y, aunque no fallara, un firmware UEFI no lo arrancaría. La ESP se crea y se monta pero no se usa. Originalmente (`daac08f`) usaban `systemd-boot` + `efi.canTouchEfiVariables`; se reemplazó en `4fa0101` al copiar el bloque de MBR. |
| P3 | El cache `nix-community.cachix.org` no se usa | 4 scripts, `nix.settings` | Se agrega a `substituters` pero sin su clave en `trusted-public-keys`, así que Nix rechaza esos binarios. Agregar la clave pública que publica nix-community.cachix.org o quitar el substituter. |
| P4 | Las contraseñas se ven en pantalla | 4 scripts, prompts | `read -rp` sin `-s` y sin confirmación. El `-s` existía (`da5a8f7`) y se perdió al pasar a `/dev/tty` (`7fb73bd`). |
| P5 | Sin manejo de errores | 4 scripts | No hay `set -euo pipefail`: si falla `parted`/`mkfs`/`mount`/`nixos-install`, el script sigue igual y termina en `poweroff`. |
| P6 | Nombres de partición incompatibles con NVMe/eMMC | scripts PC | `/dev/$diskName"1"` da `nvme0n1` + `1` = `nvme0n11` en vez de `nvme0n1p1`. |
| P7 | Entradas sin validar | 4 scripts + `createKeys` | `username` vacío o con caracteres raros (p. ej. `.`) rompe `users.users.$username` en Nix. `diskName` no se verifica antes de borrar el disco. Un `nixProfile` con `"`, `\` o `${` rompe el `configuration.nix` (y `nixos-install` falla); si no coincide con ningún `nixosConfigurations.<perfil>` del flake, falla `update`. La URL del repo solo funciona en formato scp (`git@github.com:usuario/repo.git`): una URL HTTPS o `ssh://…:22/…` queda mal porque se reemplazan **todos** los `:`. |
| P8 | Comentarios desactualizados o engañosos | 4 scripts | *"here a 8GB one is created"* (la swap es de 1 GB o 2 GB); la ESP dice *512MiB* pero se crea con `512MB`; el primer `clear` (antes de `sudo -i`) tiene el comentario *"before proceeding with user setup"*, que solo es cierto para el segundo; *"Installation of NixOS and setting 'root' password"* (no se aplica, P1). Cosmético: la línea `tmp.cleanOnBoot` está indentada con tabs. |
| P9 | Grupo `docker` sin Docker | 4 scripts | `extraGroups` incluye `docker` pero Docker no se habilita (se espera del flake). |
| P10 | README desactualizado o incompleto | `README.md` | El paso 3 dice *"con usuario 'nixi'"* (el usuario se elige al instalar desde `fdf1bc5`/`b83b24e`); la sección de PCs no explica los pasos posteriores (`connect-repo` también existe en PC); no advierte que los scripts borran el disco sin preguntar ni que solo deben correrse desde el ISO live. (El *"(Opción 1)"* repetido en PCs se corrigió en `b4f632f`.) |

### Riesgos sin verificar (comprobar en VM antes de asumirlos)

| ID | Riesgo |
|---|---|
| R1 | `createKeys` escribe `/root/.ssh/config` **antes** de que exista `/root/.ssh` (lo crea recién `ssh-keygen`). En un sistema limpio el `tee` podría fallar, y `git+ssh` no usaría la deploy key (en un segundo intento sí, porque el directorio ya existe). Mitigación posible: `sudo mkdir -p -m 700 /root/.ssh` al principio. |
| R2 | Ejecutar `connect-repo` por segunda vez: `ssh-keygen` pregunta si sobrescribir la clave, pero su salida va a `/dev/null`, así que parece colgado. |
| R3 | En discos con datos previos (más probable en PC), `parted`/`mkfs` pueden pedir confirmación leyendo de stdin, que es el propio script (§6.2). Opciones: `parted -s`, `mkfs.ext4 -F`. |
| R4 | `system.stateVersion = "26.11"` está fijo. Al 2026-11-07 la estable es **26.05** y 26.11 es *unstable* (sin release todavía), así que el valor coincide con un ISO unstable. Si se instala con el ISO estable, debería ser `"26.05"`. Revisarlo cada vez que se cambie de ISO. |

---

## 10. Cómo validar cambios (siempre aislado del sistema principal)

> 🛑 **Regla del dueño del proyecto:** ninguna prueba ni validación de estos scripts se ejecuta en el sistema principal (la máquina donde está clonado el repo). Todo lo que interprete o ejecute los scripts corre en un entorno encapsulado: el **sandbox de Nix** o un **contenedor sin red** para los chequeos estáticos (§10.2), y una **VM descartable** para la prueba real (§10.3).

No hay tests automáticos.

### 10.1 Qué se puede hacer en el host y qué no

| En el host (sistema principal) | ¿Permitido? |
|---|---|
| Leer los archivos como texto: abrirlos, `cat`, `less`, `grep`, `diff` (incluidos los de paridad de §8), `git log` / `git show` / `git diff` | ✅ Sí |
| Lanzar un entorno aislado: el `nix-build` de §10.2, `podman run --network=none …`, una VM | ✅ Sí: son el aislamiento |
| `bash -n`, `shellcheck`, `nix-instantiate` u otra herramienta sobre los scripts **directamente en el host** | ❌ No: usá §10.2 |
| Ejecutar los scripts o fragmentos de ellos: `bash script.sh`, `cat script.sh \| bash`, `curl … \| bash`, `source`, copiar y pegar líneas en una terminal, correr los `tee` de los heredocs (escriben en `/mnt/etc/nixos/`) | ❌ Nunca |
| Ejecutar los comandos del sistema instalado: `connect-repo`, `createKeys`, `update` o las líneas de §3 Fase 3 (`nixos-generate-config`, `nixos-rebuild`, `reboot`) | ❌ Nunca: son para el VPS o la PC recién instalados |

Por qué tan estricto: con `sudo` sin contraseña, un solo error (escribir `bash` en vez de `bash -n`, o agregar `| bash`) alcanza para que un script reparticione un disco (`parted … mklabel`), lo formatee y apague la máquina (`poweroff`), sin preguntar nada.

**Agentes de IA:** no corran validaciones por iniciativa propia. Si el usuario pide validar, usen solo §10.2 y muestren antes el comando exacto que van a ejecutar.

### 10.2 Chequeos estáticos (`bash -n` y `shellcheck`): en el sandbox de Nix

Desde la raíz del repo:

```bash
cat "$(nix-build --no-out-link -E '
  with import <nixpkgs> {};
  runCommand "check-install-scripts" {
    src = builtins.path { name = "install-scripts"; path = ./.; filter = p: t: lib.hasPrefix "install-" (baseNameOf p) && lib.hasSuffix ".sh" (baseNameOf p); };
    nativeBuildInputs = [ shellcheck ];
  } "cd $src; { for f in install-*.sh; do bash -n $f && echo \"bash -n OK: $f\"; done; shellcheck install-*.sh; } > $out 2>&1 || true"
')"
```

- **Por qué es seguro:** los comandos corren dentro del sandbox de builds de Nix, con un usuario sin privilegios (`nixbld`), sin red, sin `sudo`, sin acceso a tu `$HOME` ni a los discos (el `/dev` del sandbox no tiene dispositivos de bloque). Solo ven una copia de solo lectura de los cuatro `install-*.sh` en `/nix/store`: el `filter` deja afuera todo lo demás, para que ningún otro archivo de la carpeta (por ejemplo, algo sin commitear con datos privados) termine en el store, que es legible por todos los usuarios. En el host solo quedan esa copia y un archivo de texto con el resultado. Como `--no-out-link` no crea raíces de GC, el próximo garbage collection normal los elimina: no hace falta correr nada.
- **Requisito:** el sandbox de Nix tiene que estar activado. En NixOS viene así por defecto; comprobalo con `grep '^sandbox' /etc/nix/nix.conf` (debe decir `true`). Si dice `false`, **no** uses este método.
- `<nixpkgs>` tiene que resolver: `nix-instantiate --find-file nixpkgs` debe devolver una ruta.
- `bash -n` revisa **un solo archivo por invocación** (con `bash -n a.sh b.sh`, `b.sh` se toma como argumento de `a.sh` y no se revisa); por eso el `for`.
- `shellcheck` va a marcar P5 y otros detalles: es esperable. Referencia: al `a64e250` los 4 scripts pasan `bash -n`.
- Ni `bash -n` ni `shellcheck` validan el Nix de adentro de los heredocs: eso se valida en la VM (§10.3).

Alternativa sin Nix (otra máquina): un contenedor **rootless**, sin red y con el repo montado en solo lectura:

```bash
podman run --rm --network=none -v "$PWD":/src:ro -w /src docker.io/library/bash:5 \
  bash -c 'for f in install-*.sh; do bash -n "$f" && echo "bash -n OK: $f"; done'
podman run --rm --network=none -v "$PWD":/src:ro -w /src docker.io/koalaman/shellcheck:stable \
  install-gpt-for-pc.sh install-gpt.sh install-mbr-for-pc.sh install-mbr.sh
```

Nunca uses `--privileged`, `--device` ni montes `/dev` o discos del host. Preferí `podman` rootless: Docker con el grupo `docker` equivale a root en el host.

### 10.3 Prueba real: solo en una VM descartable

Lo único que prueba el comportamiento de verdad (particionado, el Nix generado, `nixos-install`, `connect-repo`/`update`) es una instalación completa, y se hace **solo** en una máquina virtual que se pueda borrar.

- **Disco:** una imagen de disco nueva y vacía (p. ej. qcow2), creada para la prueba. Nunca le pases a la VM un disco, una partición o un volumen real del host (`/dev/sdX`, `/dev/nvme…`, LVM), ni passthrough de controladoras USB/PCI: el script lo borraría. Los scripts de VPS usan `/dev/vda` fijo, así que el disco de la VM tiene que ser virtio.
- **Sin carpetas compartidas** con el host (virtiofs, 9p): dentro de la VM los scripts corren como root.
- **ISO y firmware:** el ISO de NixOS que coincida con `stateVersion` (R4). BIOS para los scripts MBR; UEFI (OVMF) para los GPT (que hoy no arrancan, P2).
- **Dónde se ejecuta:** el `curl … | bash` (o la URL raw de una rama de prueba, §8) se escribe **en la consola de la VM**. Antes de pegarlo, confirmá que la ventana activa es la de la VM y no una terminal del host. En los scripts de PC, el disco que se ingresa es el de la VM (verificalo con `lsblk` dentro de la VM).
- **El Nix generado se valida acá:** si `nixos-install` termina sin errores, el `configuration.nix` evaluó y se construyó.
- **`connect-repo`/`update`:** se prueban dentro de la VM ya instalada, con un repo de prueba o con una deploy key que después borres de GitHub.
- **Al terminar:** borrá la VM, su imagen de disco y las deploy keys de prueba que hayas cargado en GitHub.
- **Agentes de IA:** no creen ni arranquen VMs por su cuenta. Denle los pasos al usuario o, si los pide, muéstrenle antes el comando exacto.

---

## 11. Decisiones de diseño (no revertir sin motivo)

| Decisión | Commit | Motivo |
|---|---|---|
| Dos heredocs (interpolado + literal) | `a9f0198`, `c3cb08a` | Interpolar `$username`/`$diskName` sin romper el código shell de `createKeys`/`update` (§6.3). |
| `createKeys` y `update` como `writeShellScriptBin` en vez de alias | `da9847c` | Los alias con `bash -c '…'` y comillas anidadas eran frágiles; los binarios se pueden llamar entre sí. |
| `/root/.ssh/config` con `echo -e … \| sudo tee` | `30cab0b` | El heredoc anidado cerraba el heredoc externo (§6.3). |
| `sudo` por comando dentro de `createKeys` | `c22a15f`, `262276f` | `sudo -i` dentro de un script no eleva los comandos siguientes (§6.6). |
| Contraseña del usuario con `chpasswd -R /mnt` | `ae8759d` | `nixos-enter` + `passwd` no funcionaba de forma no interactiva. |
| Lectura desde `/dev/tty` | `7fb73bd` | stdin es el script (§6.2). |
| URL `:` → `/` | `da9847c` | Pasar de formato scp a una URL `git+ssh://` válida. |
| `nixos-rebuild boot` + `reboot` | `77cab70` | §6.5. |
| Deploy key sin passphrase (`-N ""`) | `6d2bf39` | Que `nixos-rebuild` como root pueda clonar sin intervención. |
| `PermitRootLogin = "no"` | `3b8644c` | Se probó `"yes"` (`4fa0101`) y se volvió a `"no"`; se entra con el usuario creado. |
| Usuario elegido al instalar (antes fijo: `nixi`) | `fdf1bc5`, `b83b24e` | Reutilizar los scripts con cualquier usuario. |
| Salida de particionado visible | `2315432` → `dd212b7` | Se ocultó y se revirtió a los 3 minutos: ver la salida ayuda a detectar errores (no hay manejo de errores, P5). |
| `configuration.nix` mínimo | `183c8b6`, `3b8644c` | Solo lo necesario para el primer acceso; el resto va en el flake. |
| `clear` antes de los prompts de usuarios | `dd212b7`, `a64e250` | Que los prompts de contraseñas no queden mezclados con la salida de `parted`/`mkfs`. |

---

## 12. Historia en breve

Todo el desarrollo ocurrió entre el 2026-11-05 y el 2026-11-07 (72 commits al `b4f632f`). Detalle en `CHANGELOG.md`.

1. **2026-11-05, mañana:** `install-mbr.sh` inicial con usuario fijo `nixi` y un `configuration.nix` completo (con comentarios por defecto, `fail2ban`, `btop`). Se agregan `createKeys` (deploy key) y un alias `update` con `bash -c` y `nixos-rebuild switch`.
2. **2026-11-05, mediodía:** `install-gpt.sh` (con `systemd-boot`), README con los comandos `curl`.
3. **2026-11-05, tarde:** muchas iteraciones para las contraseñas (`read -s`, `nixos-enter`, `/dev/tty`, `chpasswd`), `sudo` por comando, limpieza del `configuration.nix`, sudo sin contraseña. GPT pasa a GRUB (origen de P2).
4. **2026-11-05, noche:** `update` como binario, URL `:` → `/`, `boot` en vez de `switch`, arreglo del heredoc anidado.
5. **2026-11-06, mañana:** usuario elegido al instalar, división en dos heredocs, opciones `ssh` del README, scripts para PC, rediseño del README.
6. **2026-11-06, media mañana–tarde:** paridad total entre los 4 scripts, limpieza (sin `fail2ban`/`btop`/alias extra, `PermitRootLogin = "no"`), salida visible, `clear`, README con opciones y pasos numerados.
7. **2026-11-07:** reubicación del `clear` (hoy hay dos), esta documentación (`AGENTS.md`, `CHANGELOG.md`, `CLAUDE.md`) y el título *"(Opción 2)"* de GPT en la sección de PCs del README.

---

## 13. Mantenimiento de `CHANGELOG.md`

- Orden **cronológico inverso**: lo más nuevo arriba de todo; hacia abajo, lo más viejo. Lo mismo dentro de cada día.
- Una sección por día (`## AAAA-MM-DD`), en hora de Argentina (UTC−03:00), igual que los commits del autor. Usá la fecha real del cambio (`git log --date=iso`), nunca una inventada.
- Si ya existe la sección del día, agregá la entrada **arriba** dentro de esa sección.
- Cada entrada empieza con el hash corto del commit entre backticks y un prefijo de área (`Scripts`, `README`, `Docs`). Si el cambio todavía no está commiteado, usá **(sin commitear)** en lugar del hash y reemplazalo por el hash después de commitear.
- Describí lo que cambió **en el código**, no copies el mensaje del commit si no coincide con el diff (marcalo con ⚠️).

---

## 14. Checklist para cualquier cambio

1. ¿El cambio aplica a los 4 scripts? Aplicalo en los 4 y corré los `diff` de paridad (§8).
2. ¿Agregaste un prompt? `read -rp … < /dev/tty` (§6.2).
3. ¿Tocaste el `configuration.nix`? Variables de instalación → bloque 1; código de `createKeys`/`update` → bloque 2; ninguna línea igual a `EOF`; llaves balanceadas; nada de `${…}` dentro de `'' … ''` (§6.3, §6.4).
4. Chequeos estáticos (`bash -n` y `shellcheck`) **solo** en el sandbox de Nix o en un contenedor sin red (§10.2), nunca en el host. Si el cambio altera el comportamiento, probalo en una VM descartable (§10.3).
5. `CHANGELOG.md` arriba de todo; `README.md` si cambia algo visible; este archivo si cambia el flujo, la estructura o un problema conocido.
6. Commit en inglés, imperativo. Para cambios no triviales, rama + prueba en VM antes de `main` (§8, §10).
