# AGENTS.md — nixos-first-install

> Contexto completo para agentes de IA (Claude, Codex, Gemini, Copilot, etc.) y para cualquier persona que retome el proyecto.
> `CLAUDE.md` es solo un alias que importa este archivo: **editá siempre `AGENTS.md`**, nunca `CLAUDE.md`.
> Este archivo **describe** el proyecto y cambia poco. El **estado** (qué funciona, qué está probado, problemas, riesgos y correcciones) está en [`STATUS.md`](STATUS.md), que cambia casi tan seguido como el historial.
> Historial detallado commit por commit: [`CHANGELOG.md`](CHANGELOG.md) (lo más nuevo arriba).
> Revisado el **2026-11-27** contra el commit **`ec0d9a4`** más un cambio sin commitear de `install-gpt-exo.sh` por P14 (swap temporal de 8 GiB, sin core dumps y aviso de `copytoram`; ver `CHANGELOG.md`). La revisión completa de todo el documento es del 2026-11-07 (`b4f632f`). Si `git log -1` muestra otro commit, revisá lo que cambió después (`git log 1a13cba..HEAD -p`) antes de confiar ciegamente en este documento.

---

## 0. Lo mínimo antes de tocar algo

1. **Nunca ejecutes ni pruebes nada de los `install-*.sh` en el sistema principal** (la máquina donde está clonado el repo): borran y reparticionan un disco sin pedir confirmación. En el host solo se **lee** el texto; los chequeos estáticos van en el sandbox de Nix o en un contenedor sin red, y la instalación en una VM descartable (§10).
2. **Paridad:** los 4 scripts son copias; todo cambio común va en los 4 (§8). `install-gpt-exo.sh` es un script aparte, fuera de la paridad (§2).
3. **Dos heredocs** (en los 4 scripts; `install-gpt-exo.sh` no escribe `configuration.nix`): el bloque 1 solo guarda en un `let` de Nix lo que se ingresa al instalar (`$username`, `$diskName`, `$nixProfile` y, solo en VPS, `$headscaleDomain`, `$headscaleIp`); el bloque 2 (literal) tiene todo el attribute set y usa esos valores como variables de Nix (`${username}`), nunca como `$username` (§6.3).
4. **Todo `read` usa `< /dev/tty`**: el script llega por stdin (`curl … | bash`), así que stdin *es* el script (§6.1, §6.2).
5. **`main` es producción:** cada push lo descarga el próximo que ejecute el `curl`. Documentá todo cambio en `CHANGELOG.md` (y en `STATUS.md`, `README.md` o `AGENTS.md` si corresponde) (§13, §14).
6. **Leé [`STATUS.md`](STATUS.md) antes de tocar algo:** qué script está probado, qué está roto (P…), qué riesgos hay (R…) y qué falta probar.

---

## 1. Resumen rápido

- **Qué es:** 4 scripts Bash que hacen la *primera instalación* de NixOS desde el ISO live: particionan y formatean un disco, generan un `configuration.nix` mínimo, ejecutan `nixos-install` y apagan la máquina.
- **Para qué:** dejar un sistema base al que se entra por SSH y que, con un solo comando (`connect-repo`), pasa a gestionarse desde **otro repositorio con un flake de NixOS** (externo a este repo, ver §7). Además, con los scripts de VPS la máquina corre su propia **tailnet**: es servidor **headscale** (con HTTPS vía Caddy si se ingresa un dominio, o por HTTP plano con la IP si no) y a la vez nodo **tailscale** de esa tailnet. Las PCs instaladas con los scripts de PC se suman a esa tailnet como clientes con `connect-tailnet` (§3, Fase 2b; hoy solo en `install-msdos-pc.sh`).
- **Un quinto script, aparte:** `install-gpt-exo.sh`, para la tableta EXO Wings K1322 (2 en 1). Borra los discos antes de particionar y, en vez de un sistema mínimo, instala directamente el sistema del repo del flake (`nixos-install --flake`), sin `connect-repo` (§2, §3, §7.1).
- **Dónde se usa:** VPS (probado en **Upcloud** con `install-mbr.sh`, hoy `install-msdos.sh`) y PCs; `install-gpt-exo.sh`, en la EXO (el dueño también lo prueba en PCs con `sda`).
- **Cómo se ejecuta:** solo desde el ISO live de NixOS, en la máquina que se va a borrar: `curl -sSL https://raw.githubusercontent.com/mjb10/nixos-first-install/refs/heads/main/<script>.sh | bash`. ⚠️ Borra el disco sin preguntar: nunca en el host ni en una máquina con datos (§10).
- **Estado:** en [`STATUS.md`](STATUS.md) (qué script funciona y está probado, problemas conocidos, riesgos y correcciones).
- **No hay** build, tests automáticos, CI, releases, tags, licencia, `.gitignore` ni `flake.nix` (este repo **no** es un flake; el flake vive en otro repo).
- **Idiomas:** README y documentación en español (rioplatense). Mensajes del instalador en inglés; mensajes de `createKeys`/`update`/`tailnet-key` en español. Comentarios del código en inglés. Commits en inglés.
- **Dueño:** usuario de GitHub `mjb10`. Remoto: `https://github.com/mjb10/nixos-first-install.git`. Única rama: `main`.

---

## 2. Archivos del repositorio

Estructura plana, sin subdirectorios.

### Scripts de instalación

| Archivo | Nombre anterior (hasta `9884e52`/`dda3702`) | Destino | Tabla de particiones | Firmware previsto | Cargador de arranque | Disco | Swap |
|---|---|---|---|---|---|---|---|
| `install-msdos.sh` | `install-mbr.sh` | VPS | MBR (`msdos`) | BIOS | GRUB, solo BIOS | `/dev/vda` (fijo) | 1 GB |
| `install-gpt.sh` | (igual) | VPS | GPT | UEFI | GRUB, solo UEFI (`nodev`) | `/dev/vda` (fijo) | 1 GB |
| `install-msdos-pc.sh` | `install-mbr-for-pc.sh` | PC | MBR (`msdos`) | BIOS | GRUB, solo BIOS | se pregunta (`diskName`) | 2 GB |
| `install-gpt-pc.sh` | `install-gpt-for-pc.sh` | PC | GPT | UEFI de 64 y de 32 bits (y BIOS) | Limine | se pregunta (`diskName`) | 2 GB |
| `install-gpt-exo.sh` | (nuevo, `8a2a71f`) | EXO Wings K1322 (y PCs con UEFI) | GPT | UEFI de 32 bits (D-64 de `nixos-ferchu`) | el que defina el flake (para la EXO, Limine con `BOOTIA32.EFI`) | detectado solo (la eMMC, p. ej. `mmcblk1`) | 2 GB |

Las URLs raw con los nombres anteriores ya no existen en `main` (devuelven 404).

Los 4 scripts son **casi idénticos** (copias). Solo difieren en:

1. **Particionado/formateo/montaje** (MBR vs GPT, §4).
2. **VPS vs PC:** los de PC piden el nombre del disco (justo después de `sudo -i`, o sea que responde root) y usan `/dev/$diskName`, `/dev/$diskName"1"`, etc. (en el `configuration.nix`, con la variable `diskName` del `let`: `boot.loader.grub.device = "/dev/${diskName}"` en `install-msdos-pc.sh` y `boot.loader.limine.biosDevice = "/dev/${diskName}"` en `install-gpt-pc.sh`); `update` le pasa al flake `DISK=/dev/${diskName}` (en VPS, `DISK=/dev/vda`, §7); la swap es de 2 GB en vez de 1 GB.
3. **Tailnet, VPS vs PC (desde el 2026-11-19):** los de VPS son el **servidor** headscale: prompt del dominio/IP, `headscaleDomain`/`headscaleIp` en el `let`, `services.headscale`, `services.caddy`, `systemd.services.tailnet-join` y el comando `tailnet-key`. Los de PC son **clientes**: nada de eso, y en su lugar el comando `connect-tailnet` (§3, Fase 2b). Todos tienen `services.tailscale.enable = true`, con comentarios distintos.
4. **Cargador de arranque (desde el 2026-11-25), según la tabla de particiones:** los MSDOS (VPS y PC) usan **GRUB solo BIOS** (`device = "/dev/vda"`, en PC `"/dev/${diskName}"`, con `#efiSupport = true;` y `#efiInstallAsRemovable = true;` comentados). `install-gpt.sh` usa **GRUB solo UEFI** (`device = "nodev"`, `efiSupport = true`, `efiInstallAsRemovable = true`). `install-gpt-pc.sh` usa **Limine** (`biosSupport = true`, `biosDevice = "/dev/${diskName}"`, `efiSupport = true`; la línea de `biosSupport` está indentada con un tab). Desde `c8d9216`, ese Limine se compila también para 32 bits (`limine = pkgs.limine.override { targets = [ "i686" "x86_64" ]; }` en el `let`, `package = limine`) y copia `BOOTIA32.EFI` a `EFI/BOOT/` de la ESP, para firmwares UEFI de 32 bits. Ver §5; el estado de cada uno, en `STATUS.md`.
5. **Substituters, VPS vs PC (desde `f35753d`):** en los de PC, `https://nix-community.cachix.org` está comentado; en los de VPS sigue activo (P3).
6. **Segundo `clear`:** ya no es una diferencia. Está comentado (`#clear`) en los 4: en los de PC desde `e6718da`/`12287c9`, en los de VPS desde `69961bf`.
7. **`install-gpt-pc.sh` vs `install-msdos-pc.sh` (desde `f1fcd62`):** además del particionado y del cargador de arranque (punto 4), en el GPT están comentados `tailscale` en `environment.systemPackages` (el comando existe igual, porque lo agrega `services.tailscale`) y todo el `connect-tailnet`. Desde `f50b589` tiene activa una partición BIOS (`mkpart BIOS 1MiB 2MiB`, `set 4 bios_grub on`, agregada en `17ecf14` y comentada después), y la ESP arranca en `2MB`.
8. Diferencias cosméticas de espacios: en los de VPS, `-N ""  > /dev/null` y `tee /root/.github_repo_url  > /dev/null` llevan doble espacio.

Todo lo demás (prompts, `configuration.nix`, `createKeys`, `update`, cierre) es igual y **debe mantenerse igual** (§8).

### `install-gpt-exo.sh`: un script aparte

Es para la EXO Wings K1322 (2 en 1, Intel Bay Trail Z3735F, 2 GB de RAM, eMMC de 29,1 GB, UEFI de 32 bits, lector de microSD). Nació de `install-gpt-pc.sh` (`8a2a71f`), pero **no entra en la paridad**: los cambios de los 4 no se copian acá ni al revés, salvo que el dueño lo pida. Diferencias principales (el flujo completo está en §3):

- **Disco detectado solo:** elige la eMMC (tipo `MMC` en `/sys/block/*/device/type`) y descarta la USB del instalador (la que tiene montado `/iso`), los removibles, los discos USB, las tarjetas SD y las áreas `mmcblk*boot*`/`rpmb` de la eMMC. Si no puede decidir, pregunta. Muestra la lista con sus particiones y pide `YES`; con Enter se elige otro disco. Los nombres de partición llevan `p` si el disco termina en dígito (`mmcblk1p1`, `nvme0n1p1`).
- **Discos borrados antes de particionar:** `release_disk` desmonta y apaga la swap de lo que dejó una corrida anterior, y corta sin borrar nada si algo lo sigue usando (un montaje, la swap, LVM, RAID o cifrado). `wipe_disk` deja el disco solo con espacio libre: `wipefs` de cada partición y del disco. Nunca toca `mmcblk*boot0/boot1`.
- **Otros discos (la microSD):** ofrece borrarlos, cada uno con su propio `YES`, y dejarlos como una partición ext4 vacía para archivos (`files_disk`: tabla MSDOS, etiqueta `microSD` o `Archivos`, raíz `root:users` con modo `2775`). No se montan ni entran en la configuración de NixOS.
- **Todas las preguntas antes de tocar los discos:** la contraseña de root (dos veces, con `ask_password`), el perfil de Nix, la deploy key y la URL del repo con su rama, que se comprueban con `git ls-remote`.
- **No escribe `configuration.nix`** (no hay heredocs ni `let`) **y no crea usuarios:** instala con `nixos-install --flake` y el sistema entero sale del flake (§7.1). Solo pone la contraseña de root, con `chpasswd`.
- **Errores:** con `fail()`/`cancel()`, que muestran el mensaje y cortan sin apagar (y vacían el resto del script que llega por stdin). `nixos-install` se puede reintentar.
- **Reanudación:** si el disco elegido ya tiene las 4 particiones que crea el script (`has_install_layout`: GPT con los nombres `root`, `swap`, `ESP` y `BIOS`, en ese orden), volver a correrlo ofrece `YES` para seguir sobre ellas o `ERASE` para borrar y empezar de cero. Con `YES` (`resume=1`): no borra ni particiona, formatea solo las particiones que no tienen todavía su sistema de archivos (`format_part`, con `blkid -p`) y vuelve a correr `nixos-install`, que reutiliza lo que ya está en el store y en la caché de `/mnt`. Las preguntas se repiten siempre; la deploy key se reutiliza si sigue la misma sesión del live. Antes de montar, borra lo que una corrida vieja haya dejado en `/mnt` cuando no era un montaje (en la RAM del live).
- **Memoria durante `nixos-install` (P14):** los programas del live salen de la imagen squashfs del USB. Si la evaluación del flake llena la RAM, el kernel los descarta y los relee del USB una y otra vez, y si una lectura falla, muere systemd y hay un kernel panic. Por eso, antes de instalar:
  - un archivo de swap temporal de 8 GiB (`installSwap`, `/mnt/.install-swap`). Se crea después de `nixos-generate-config`, que igual ignora los archivos de swap, y se borra al final;
  - `vm.swappiness=150`, para que pase a swap la memoria del evaluador antes que descartar programas;
  - `vm.min_free_kbytes=65536`, memoria libre para los drivers del USB y del disco;
  - `ulimit -c 0`, porque los core dumps de `nix` iban a la RAM del live;
  - un aviso si `/iso` no es `tmpfs`: la solución de fondo es arrancar el USB con `copytoram` (*"Copy ISO Files to RAM"* en el menú del ISO), y así el live no lee del USB después de arrancar.

  Al principio del borrado se apaga ese archivo de swap si quedó activo, o `/mnt` no se podría desmontar.
- **Particionado propio** (§4).

### Documentación

- `README.md` — instrucciones para el usuario final (en español). Tiene errores conocidos (P10).
- `AGENTS.md` — este archivo: qué es el proyecto, cómo funciona y cómo se trabaja. Cambia poco.
- `STATUS.md` — estado actual: qué funciona y está probado, qué falta probar, problemas conocidos (P…), riesgos (R…), correcciones y paridad. Cambia casi a la par del `CHANGELOG.md`.
- `CHANGELOG.md` — historial de cambios, lo más nuevo arriba (§13).
- `CLAUDE.md` — alias: solo importa `AGENTS.md` con la sintaxis `@AGENTS.md` de Claude Code.

---

## 3. Flujo completo, de punta a punta

### Fase 1 — Instalación (en el ISO live de NixOS)

El ISO minimal de NixOS inicia sesión solo como el usuario `nixos`, que tiene `sudo` sin contraseña. El usuario ejecuta el `curl … | bash` del README.

1. `clear` → limpia la pantalla (todavía como usuario `nixos`).
2. `sudo -i` → el resto del script corre como root (§6.1 explica por qué funciona y por qué depende del pipe).
3. **Solo PC:** pide el nombre del disco (`vda`, `sda`, …) → variable `diskName`.
4. Particiona con `parted -s`, formatea (`mkfs.ext4 -F`), monta en `/mnt` y activa la swap (§4). La salida de estos comandos queda visible a propósito.
5. `nixos-generate-config --root /mnt` → crea `hardware-configuration.nix` y un `configuration.nix` por defecto.
6. `clear` (solo en VPS: en PC está comentado, §2) y pide, leyendo de `/dev/tty`: contraseña de root (`passwordRoot`), nombre del nuevo usuario (`username`), su contraseña (`password`) y el nombre del perfil de Nix (`nixProfile`, `nixos` si se deja vacío): el nombre de la configuración del flake que va a construir `update` (`nixosConfigurations.<perfil>`, §7), y, **solo en los scripts de VPS**, el dominio público de headscale (`headscaleDomain`, p. ej. `headscale.example.com`; se le sacan `http://`, `https://` y la `/` final si se escriben). Si el dominio queda vacío (modo solo IP), muestra la IP detectada (la de origen de la ruta por defecto: `ip -4 route get 1.1.1.1`) y pide la IP para headscale (`headscaleIp`; vacío = la detectada; se repite hasta que haya una). Al final muestra la URL resultante. Se ven en pantalla (P4).
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

### Fase 2b — Tailnet: el VPS es servidor headscale (automático) y las PCs se suman como clientes (`connect-tailnet`)

> ⚠️ Igual que la Fase 3: corre **en el sistema instalado**, nunca en el host.

Todo lo que sigue, hasta "Otros dispositivos", es **solo de los scripts de VPS**.

- **Dos modos**, según si se ingresó un dominio al instalar:
  - **Con dominio (recomendado):** `server_url = https://<headscaleDomain>`. `headscale` escucha solo en `127.0.0.1:8080` y Caddy lo publica con HTTPS. Antes del primer arranque, el dominio tiene que tener un registro DNS A/AAAA hacia la IP pública de la máquina, con los puertos 80 y 443 accesibles (el firewall está apagado): Caddy los usa para sacar el certificado de Let's Encrypt, y si el DNS todavía no apunta, reintenta solo.
  - **Solo IP (dominio vacío):** `server_url = http://<headscaleIp>:8080`. `headscale` escucha en `0.0.0.0:8080` por HTTP plano y Caddy no se habilita (`lib.mkIf (headscaleDomain != "")`). Riesgos: sin TLS, la clave pública del servidor se baja por HTTP la primera vez, así que nada autentica al servidor (alguien en el medio podría hacerse pasar por headscale y manejar la coordinación; el tráfico entre nodos sigue cifrado con WireGuard); la documentación de headscale solo muestra `https://` para las apps, y alguna podría no aceptar `http` (sin verificar); y la IP queda fija en todos los dispositivos, así que si cambia hay que volver a registrarlos. Detrás de NAT hay que ingresar la IP pública y redirigir el puerto 8080.
- **Servidor:** MagicDNS con `base_domain = "tailnet.internal"` (los nodos quedan como `<hostname>.tailnet.internal`) y `override_local_dns = false` (no se pisan los DNS de cada dispositivo). Sin política de ACL: todos los nodos se ven entre sí. Los DERP son los públicos de Tailscale (el DERP embebido de headscale está apagado).
- **La máquina se une sola a su tailnet** con el servicio `tailnet-join` (systemd, oneshot, en cada arranque): espera a que respondan `headscale` y `tailscaled`; si el estado de Tailscale es `NeedsLogin` crea (si falta) el usuario de headscale con el mismo nombre que el usuario de Linux, genera una pre-auth key de un solo uso que vence en 10 minutos y ejecuta `tailscale up --login-server http://127.0.0.1:8080 --auth-key … --accept-dns=false --timeout 2m`. Si ya está en la tailnet (`Running`) o se bajó a mano (`Stopped`, con `tailscale down`), no hace nada. La clave nunca se muestra ni se guarda. Usa el login server local para no depender de que el certificado HTTPS ya exista; la propia máquina no usa MagicDNS. Si falla, se ve con `systemctl status tailnet-join` y se reintenta con `sudo systemctl restart tailnet-join`.
- **Otros dispositivos:** el comando `tailnet-key` (`writeShellScriptBin`, por SSH en la máquina) crea (si falta) el mismo usuario de headscale, genera una pre-auth key de un solo uso que vence en 1 hora y muestra el comando para el dispositivo nuevo: `sudo tailscale up --login-server <server_url> --auth-key <clave>` (toma la URL de `config.services.headscale.settings.server_url`, así que sirve en los dos modos). En las apps (Android, iOS, macOS, Windows) se configura `<server_url>` como servidor personalizado; la página de login muestra `headscale auth register --auth-id … --user USERNAME`, que se ejecuta en la máquina con `sudo` (en headscale 0.29, `nodes register` está deprecado).
- **PCs instaladas con estos scripts (solo scripts de PC):** no corren headscale. Tienen el cliente tailscale habilitado y el comando `connect-tailnet` (⚠️ desde `f1fcd62`, solo en `install-msdos-pc.sh`: en `install-gpt-pc.sh` está comentado, y para sumar esa PC hay que ejecutar a mano el `sudo tailscale up …` que muestra `tailnet-key`) (`writeShellScriptBin`, interactivo, `read` normal como `createKeys`): pide la URL de headscale y la pre-auth key de `tailnet-key` (la clave con `read -s`, sin mostrarla), ejecuta `sudo tailscale up --login-server <url> --auth-key <clave> --timeout 2m` y muestra la IP de la tailnet (`tailscale ip -4`). No guarda nada en disco. Si falla (clave vencida o ya usada, URL mal escrita), sale con código 1 y se reintenta con otra clave. Sin `--accept-dns=false`: las PCs usan MagicDNS. Si la PC ya estaba en una tailnet con otras opciones, `tailscale up` puede pedir `--reset` o un `sudo tailscale logout` previo.

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
   - Pide el nombre de la rama del repo del flake (`read … rama < /dev/tty`). Si se deja vacío, se usa la rama por defecto del repo (`main`, `master` o la que tenga).
   - Arma la URL del flake en la variable `repo`: `git+ssh://<url>?ref=<rama>#<perfil>` si se ingresó una rama, o `git+ssh://<url>#<perfil>` si no (§6.7).
   - `sudo nixos-generate-config` → regenera `/etc/nixos/hardware-configuration.nix` (no pisa `configuration.nix` porque ya existe).
   - `sudo DISK=/dev/<disco> nixos-rebuild boot --flake "$repo" --refresh --impure --no-write-lock-file -I hardware=/etc/nixos/hardware-configuration.nix` (`DISK=/dev/vda` en VPS; en PC, el disco elegido al instalar; §7)
6. Solo si `update` terminó bien (`if update; then … fi`): *"Actualización completada."*, `sleep 5` y `sudo reboot` → arranca la generación construida desde el flake. Si falló (rama inexistente, deploy key sin cargar, perfil que no existe, etc.), muestra *"La actualización falló: no se reinicia el sistema."*, no reinicia y sale con código 1. Se reintenta con `update && sudo reboot`, no con `connect-repo` (regenera la clave, R2).

Después, `update` queda disponible para volver a sincronizar con el repo, y cada vez vuelve a preguntar la rama (mientras el flake siga incluyendo estos scripts; el propio código dice *"You can delete this script"*).

### `install-gpt-exo.sh`: instalación directa desde el flake

> ⚠️ Igual que los otros: corre solo en el live de la máquina que se va a borrar, nunca en el host.

Reemplaza las fases 1 a 3: no hay sistema mínimo ni `connect-repo`.

1. **Preguntas,** después de `clear` y `sudo -i`, sin tocar los discos:
   - contraseña de root y perfil de Nix;
   - la deploy key: se escribe `/root/.ssh/config` en el live y se crea la clave (o se reutiliza si ya existe en la misma sesión), y se muestra para cargarla en GitHub;
   - la URL SSH del repo (formato scp; la https se rechaza) y la rama. Se comprueban con `git ls-remote --exit-code`, y si fallan vuelve a preguntar.
2. **Disco:** lo detecta, muestra la lista, pide `YES` y ofrece borrar los otros discos. Si el disco ya tiene las particiones de una corrida anterior, pide `YES` para seguir sobre ellas o `ERASE` para borrarlo (§2, "Reanudación").
3. **Borrado y particionado:** `umount -R /mnt`, `release_disk` y `wipe_disk` de cada disco (menos el de instalación, si se sigue una corrida anterior); `files_disk` de los discos extra; después particiona (salvo al seguir), espera a udev, formatea (al seguir, solo lo que falta), vacía `/mnt` si quedó algo en la RAM, monta y activa la swap.
4. **Hardware:** `nixos-generate-config --root /mnt --show-hardware-config` escribe solo `/mnt/etc/nixos/hardware-configuration.nix`. Se copia también a `/etc/nixos/` del live.
5. **Instalación:** `XDG_CACHE_HOME=/mnt/.install-cache DISK=<disco> nixos-install --flake "git+ssh://<url>[?ref=<rama>]#<perfil>" --impure -I hardware=/mnt/etc/nixos/hardware-configuration.nix --no-channel-copy --no-root-passwd --max-jobs 1 < /dev/null`. Las cachés de Nix van al disco nuevo y no a la RAM del live (los temporales ya los pone ahí `nixos-install`). Si falla: Enter reintenta, otro nombre prueba con ese perfil y `STOP` corta.
6. **Al final:**
   - `chpasswd` de root;
   - copia a `/mnt/root/.ssh/` la deploy key, su `.pub`, `config` y `known_hosts`, y escribe `/mnt/root/.github_repo_url` (en el formato de siempre, `git@github.com/usuario/repo.git`);
   - `nixos-enter --root /mnt -c 'nix-collect-garbage'`, que borra lo que dejaron las compilaciones (la generación instalada queda protegida por el perfil `system`);
   - `poweroff`.

Motivo (pedido del dueño, 2026-11-26): con el camino de los 4 scripts, la primera generación se construye con el nixpkgs del ISO y la del flake con el de su `flake.lock`, así que casi no comparten nada. En la EXO, el primer `nh clean all` después de `connect-repo` liberaba unos 11 GB.

---

## 4. Esquema de particiones

| Script | Partición 1 | Partición 2 | Partición 3 |
|---|---|---|---|
| `install-msdos.sh` | root ext4, etiqueta `nixos`, `1MB` → `-1GB`, flag `boot` | swap, etiqueta `swap`, `-1GB` → `100%` | — |
| `install-msdos-pc.sh` | igual, hasta `-2GB` | swap `-2GB` → `100%` | — |
| `install-gpt.sh` | root ext4 `nixos`, `512MB` → `-1GB` | swap `swap`, `-1GB` → `100%` | ESP FAT32, etiqueta `boot`, `1MB` → `512MB`, flag `esp`, montada en `/mnt/boot` |
| `install-gpt-pc.sh` | root ext4 `nixos`, `1024MB` → `-2GB` | swap `-2GB` → `100%` | ESP FAT32 `boot`, `2MB` → `1024MB` (desde `f50b589`; antes `1MB`, de `56b7b24`), flag `esp`, montada en `/mnt/boot`. Más una partición 4 BIOS boot, `1MiB` → `2MiB` (`bios_grub`) |
| `install-gpt-exo.sh` | root ext4 `nixos`, `1024MiB` → `-2GB` | swap `-2GB` → `100%` | ESP FAT32 `boot`, `1MB` → `512MB`, flag `esp`, montada en `/mnt/boot`. Más una partición 4 BIOS boot, `512MiB` → `1024MiB` (`bios_grub`) |

- En GPT la ESP es la **partición 3** aunque físicamente esté al principio del disco, porque se crea última. Los `mkfs`/`mount` dependen de esa numeración.
- Los scripts MSDOS **no tienen ninguna partición FAT**: `/boot` queda dentro de la ext4. Por eso usan GRUB solo BIOS: Limine solo lee particiones FAT (se usó desde `f35753d` y se revirtió el 2026-11-25).
- `install-gpt-pc.sh` tiene una partición 4 BIOS boot (`1MiB` → `2MiB`, flag `bios_grub`). Se agregó en `17ecf14` para GRUB en modo BIOS sobre GPT, se comentó después y está activa de nuevo desde `f50b589`; Limine no la usa explícitamente (sin `partitionIndex`, R5). `install-gpt.sh` no tiene.
- En `install-gpt-exo.sh`, la ESP y la partición BIOS ocupan el primer GiB, y root arranca justo donde termina la BIOS. Las unidades importan: `1024MB` son 976,6 MiB, y con eso root se superponía con la BIOS (P12, corregido usando `1024MiB`).
- En `install-gpt-exo.sh`, entre el último `parted` y el primer `mkfs` hay `udevadm settle` y una espera a que existan las 4 particiones: cada vez que `parted` cierra el disco, udev vuelve a leer la tabla y los `/dev/<disco>p*` pueden desaparecer un momento (P13). Si falla el particionado, el formateo o el montaje, el script corta con `fail`: sin root montado, `/mnt` es la RAM del live.
- Dispositivos: VPS usa `/dev/vda1..3`; PC usa `/dev/$diskName"1"..` (no sirve para NVMe/eMMC, P6); `install-gpt-exo.sh` agrega `p` si el nombre del disco termina en dígito (`/dev/mmcblk1p1`).
- Desde el 2026-11-25, los 4 usan `parted -s` (modo script: nunca pide confirmación) y `mkfs.ext4 -F` (formatea aunque haya un sistema de archivos previo). Con eso se resolvió R3.

---

## 5. `configuration.nix` que genera el instalador

Resultado (igual en los 4 scripts salvo el cargador de arranque, los substituters y la tailnet: servidor en VPS, cliente en PC, §2). `install-gpt-exo.sh` no genera este archivo desde el 2026-11-26: el sistema sale entero del flake (§3, §7.1).

- `let nixProfileName = "<perfil>"; username = "<usuario>"; … in` antes del attribute set: los valores ingresados al instalar. En VPS, también `headscaleDomain = "<dominio>"; headscaleIp = "<ip>";` (con dominio, `headscaleIp` queda vacío; en modo solo IP, `headscaleDomain` queda vacío). En PC, también `diskName = "<disco>";`. `update` usa `nixProfileName` como `#<perfil>` (§6.4); el resto del archivo usa `username`, `headscaleDomain`, `headscaleIp` y `diskName` (§6.3).
- `imports = [ ./hardware-configuration.nix ];`
- Cargador de arranque (§2, punto 4):
  - `install-msdos.sh` e `install-msdos-pc.sh`: `boot.loader.grub = { enable = true; device = "/dev/vda"; }` (PC: `"/dev/${diskName}"`), con `#efiSupport = true;` y `#efiInstallAsRemovable = true;` comentados (GRUB solo BIOS).
  - `install-gpt.sh`: `boot.loader.grub = { enable = true; device = "nodev"; efiSupport = true; efiInstallAsRemovable = true; }` (GRUB solo UEFI, en la ESP montada en `/boot`; sin `canTouchEfiVariables`, se instala como "removable" en `EFI/BOOT/BOOTX64.EFI`).
  - `install-gpt-pc.sh`: `boot.loader.limine = { enable = true; biosSupport = true; biosDevice = "/dev/${diskName}"; efiSupport = true; package = limine; additionalFiles."EFI/BOOT/BOOTIA32.EFI" = …; }` (R5), con `limine` compilado para `i686` y `x86_64` en el `let` (`c8d9216`). Con Limine, NixOS desactiva GRUB solo (`boot.loader.grub.enable = lib.mkDefault false`).
- `boot.kernelPackages = pkgs.linuxPackages_latest;`
- `boot.tmp.cleanOnBoot = true;`
- `nix.settings`: `experimental-features = [ "nix-command" "flakes" ]`, `max-jobs = "auto"`, `substituters = [ cache.nixos.org, nix-community.cachix.org ]` en VPS (P3); en PC, solo `cache.nixos.org` (el otro está comentado desde `f35753d`).
- `networking.hostName = "nixos";`, `networking.networkmanager.enable = true;`
- `time.timeZone = "America/Argentina/Buenos_Aires";`
- `users.users.<username>`: `isNormalUser = true`, `extraGroups = [ "wheel" "docker" ]` (P9), `packages = [ tree ]`.
- `security.sudo.extraRules`: `<username>` puede ejecutar `ALL` con `NOPASSWD`.
- `environment.systemPackages`: `git`, `vim`, `tailscale`, `createKeys` y `update` (`writeShellScriptBin`), más `tailnet-key` en VPS o `connect-tailnet` en PC (también `writeShellScriptBin`). En `install-gpt-pc.sh`, `tailscale` y `connect-tailnet` están comentados (`f1fcd62`); el comando `tailscale` existe igual porque `services.tailscale` agrega el paquete. En VPS, el módulo de headscale agrega además el paquete `headscale` (la CLI de administración, con `sudo`).
- `environment.shellAliases.connect-repo = "createKeys";`
- `services.headscale` (solo VPS): `port = 8080`; con dominio, `address = "127.0.0.1"` y `settings.server_url = "https://${headscaleDomain}"`; sin dominio, `address = "0.0.0.0"` y `settings.server_url = "http://${headscaleIp}:8080"` (el puerto sale de `config.services.headscale.port`); `settings.dns = { magic_dns = true; base_domain = "tailnet.internal"; override_local_dns = false; }` (§3, Fase 2b).
- `services.caddy` (solo VPS y solo con dominio, `lib.mkIf (headscaleDomain != "")`): `virtualHosts.${headscaleDomain}` con `reverse_proxy 127.0.0.1:<puerto de headscale>` y HTTPS automático.
- `services.tailscale.enable = true;` (cliente, en los 4).
- `systemd.services.tailnet-join` (solo VPS): une la máquina a su propia tailnet (§3, Fase 2b).
- `services.openssh`: `enable = true`, `PermitRootLogin = "no"`, `PasswordAuthentication = true`, `AllowGroups = [ "wheel" ]`.
- `networking.firewall.enable = false;`
- `system.stateVersion = "26.11";` (fijo; ver R4).

Es una configuración **deliberadamente permisiva y transitoria** (firewall apagado, login por contraseña, sudo sin contraseña): su único objetivo es permitir el primer acceso por SSH y el `connect-repo`. El endurecimiento le corresponde al flake externo. Excepción: la tailnet (en VPS, headscale + Caddy + tailscale; en PC, tailscale) es una parte **permanente**, pedida por el dueño del proyecto; su estado vive en `/var/lib/headscale` y `/var/lib/tailscale` y sobrevive a `connect-repo` solo si el flake la mantiene (§7).

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

Como stdin es el propio script, un `read` normal se "comería" las líneas siguientes del script. Por eso todos los prompts usan `read -rp "…" variable < /dev/tty`. Cualquier prompt nuevo **debe** hacer lo mismo. Lo mismo aplica a cualquier comando que pueda pedir confirmación interactiva (R3). Y a los comandos que lanzan otros programas que podrían leer stdin aunque no pregunten nada: en `install-gpt-exo.sh`, `git ls-remote`, `ssh-keygen`, `nixos-install` (que clona por `git`/`ssh`) y `nixos-enter` van con `< /dev/null`. Esto rige solo para el instalador: `createKeys` corre en una sesión SSH interactiva y usa `read` normal. El prompt de la rama de `update` igual lee de `/dev/tty`. Sin terminal (p. ej. `ssh host update` sin `-t`), la redirección falla, `rama` queda vacía y se usa la rama por defecto.

### 6.3 El `configuration.nix` se escribe con DOS heredocs

```bash
tee /mnt/etc/nixos/configuration.nix > /dev/null << EOF      # bloque 1: SIN comillas
  { config, lib, pkgs, ... }:
  let nixProfileName = "$nixProfile"; username = "$username"; diskName = "$diskName"; in
EOF

tee -a /mnt/etc/nixos/configuration.nix << 'EOF' >/dev/null  # bloque 2: CON comillas, append
  …abre `{`, imports, boot, nix.settings, red, usuario, sudo, systemPackages (createKeys, update), alias, openssh, firewall, stateVersion y cierra `}`…
EOF
```

(`diskName` solo existe en los scripts de PC.)

- **Bloque 1 (`<< EOF`, sin comillas):** bash expande variables al instalar. Contiene **solo** el encabezado del módulo y el `let … in`, donde se guardan como strings de Nix los valores ingresados (`$nixProfile`, `$username` y, en PC, `$diskName`). Cualquier `$`, `$(…)` o comilla invertida también se expandiría: para un `$` literal usá `\$`.
- **Bloque 2 (`<< 'EOF'`, con comillas):** se copia literal. Contiene **todo** el attribute set. Los valores de la instalación se usan acá como **variables de Nix** del `let`, nunca como `$var` de bash: `users.users.${username}`, `users = [ username ];`, `device = "/dev/${diskName}";`, `${nixProfileName}`. Un `$username` acá llega tal cual al archivo: en una ruta de atributos es un error de sintaxis (*"unexpected invalid token"*, pasó en `0198bc8`) y dentro de un string de Nix es texto literal, sin error (la regla de sudo quedaba para un usuario llamado `$username`). El código shell de `createKeys`/`update` (`$repoUrl`, `$(tr …)`, etc.) también va acá porque debe llegar intacto para ejecutarse **en tiempo de uso**, no al instalar.
- El bloque 1 termina en `in` y el bloque 2 abre y cierra el attribute set (`{` … `}`). El encabezado `{ config, lib, pkgs, ... }:` va **una sola vez**, en el bloque 1: repetido al principio del bloque 2, el módulo devolvería una función en vez de un attribute set (pasó en `install-gpt.sh` en `0198bc8`).
- **Ninguna línea del contenido puede ser exactamente `EOF`:** cerraría el heredoc antes de tiempo, y todo lo que sigue se ejecutaría **como comandos de shell en el ISO, como root**. Pasó en `da9847c` (heredoc anidado para `/root/.ssh/config`, cuyo código siguiente incluía `sudo reboot`) y se arregló en `30cab0b` con `echo -e "…\n…" | sudo tee`.
- Antes de `c3cb08a` todo estaba en un único heredoc; en `a9f0198` se le sacaron las comillas para interpolar `$username`, lo que rompía el código de `createKeys` (se ejecutaba `$(tr …)` al instalar). La división en dos bloques es la solución: **no la deshagas**.

### 6.4 Strings `''…''` de Nix dentro de `writeShellScriptBin`

`createKeys` y `update` son strings multilínea de Nix (`'' … ''`). Dentro de ellos `${…}` es **interpolación de Nix**, no de bash: `${repo_url}` hacía fallar la evaluación (arreglado en `6aef331` usando `$repo_url`). Usá `$var` sin llaves o escapalo como `''${var}`. Para escribir `''` literal se usa `'''`. Excepción intencional: `update` usa `${nixProfileName}` para leer la variable del `let` del bloque 1 (la interpola Nix al construir el sistema) y la guarda en la variable de bash `nixProfileVar`. Lo mismo hacen `tailnet-key` y el `script` del servicio `tailnet-join` (también es un string `''…''`) con `${username}`, `${lib.getExe pkgs.jq}`, `${config.services.headscale.settings.server_url}` y `${toString config.services.headscale.port}`: todos son interpolaciones de Nix a propósito; las variables de bash de esos scripts (`$user`, `$userId`, `$key`, `$state`) van sin llaves.

### 6.5 `nixos-rebuild boot` + `reboot` (no `switch`)

`update` construye la nueva generación y la deja como predeterminada para el próximo arranque; `createKeys` reinicia después, solo si `update` terminó sin error. Se cambió de `switch` a `boot` en `77cab70`: el cambio de configuración (red, SSH, usuarios) se aplica en un arranque limpio en vez de en caliente sobre la sesión SSH activa.

### 6.6 `sudo` por comando dentro de `createKeys`/`update`

El usuario entra por SSH sin privilegios, así que cada comando que toca `/root` o el sistema lleva su propio `sudo` (sudo sin contraseña por `extraRules`). Un `sudo -i` dentro de un script **no** eleva las líneas siguientes (se probó y se descartó en `c22a15f`).

### 6.7 URL del flake: `?ref=` solo si hay rama, y antes del `#`

`update` arma la URL en la variable de bash `repo` con un `if`: agrega `?ref=<rama>` solo si se ingresó una rama. Si no, no hay `?ref=` y Nix usa la rama por defecto del repo.

- **El orden importa:** en una URL de flake, todo lo que sigue al `#` es el atributo, así que la query va **antes** del fragmento: `git+ssh://<url>?ref=<rama>#<perfil>`. Con `…#<perfil>?ref=<rama>`, `nixos-rebuild` buscaría `nixosConfigurations."<perfil>?ref=<rama>"` y fallaría, aunque la rama esté vacía (`#<perfil>?ref=`).
- **`if` en vez de `${rama:+…}`:** dentro de `'' … ''`, `${…}` es interpolación de Nix (§6.4).

---

## 7. Contrato con el repositorio externo del flake

Este repo **no** contiene la configuración final; `update` la trae de otro repo. Ese repo debe cumplir con:

1. Ser un flake en la raíz, accesible por SSH en GitHub con la deploy key generada (`Host github.com` está fijo en `/root/.ssh/config`).
2. Exponer **`nixosConfigurations.<perfil>`**, donde `<perfil>` es el nombre de perfil de Nix ingresado al instalar (`nixos` por defecto; queda fijo en `update` vía `nixProfileName`).
3. Tolerar `--impure`: se evalúa con `-I hardware=/etc/nixos/hardware-configuration.nix`, así que puede importar el hardware con `<hardware>` o con la ruta absoluta `/etc/nixos/hardware-configuration.nix`.
   - `update` también pasa el disco de instalación como **variable de entorno**: `sudo DISK=/dev/<disco> nixos-rebuild …` (en PC, el `diskName` ingresado al instalar; en VPS, `/dev/vda`). El flake lo lee con `builtins.getEnv "DISK"`: es un string común con la ruta completa (`"/dev/sda"`), se puede interpolar normalmente (`"${disk}"`) y, si no está definido (por ejemplo, con un `nixos-rebuild` hecho a mano), devuelve `""` en vez de fallar. Ejemplo: `boot.loader.grub.device = let d = builtins.getEnv "DISK"; in if d != "" then d else "/dev/vda";`. Funciona porque `update` usa `--impure` (sin eso, `getEnv` siempre da `""`) y porque `nixos-rebuild` evalúa el flake con `nix build` heredando el entorno (verificado en el código de `nixos-rebuild-ng`: solo `switch-to-configuration` corre con entorno restringido). `sudo DISK=…` está permitido porque la regla de sudo del usuario es `ALL` (implica `SETENV`). Antes de `5bc319e` se pasaba como `disk=$diskName` suelto y `update` fallaba en PC; se descartó `-I disk=…` porque lo convierte en un *path* de Nix (interpolarlo intentaría copiar `/dev/<disco>` al store) y, si falta, la evaluación falla.
4. `--no-write-lock-file` y `--refresh`: siempre toma el último commit de la rama por defecto (o de la rama que se ingrese en `update`, §6.7) y no escribe `flake.lock` (que conviene tener commiteado en ese repo).
5. Definir el bootloader correcto para el disco (p. ej. GRUB en `/dev/vda` en Upcloud; las PCs GPT se instalan con Limine, así que para esas el flake tiene que declarar Limine o pasar a otro cargador sabiendo que el de la instalación queda en el disco), el usuario creado (con `wheel` y sudo, o `update` dejará de funcionar) y el endurecimiento de seguridad.
6. Si usa `users.mutableUsers = false`, las contraseñas puestas por el instalador con `chpasswd` se pierden: tiene que declararlas (`hashedPassword`, etc.).
7. Si no incluye `createKeys`/`update`, esos comandos desaparecen tras el primer reinicio. Si copia su código, tiene que definir `nixProfileName` (o reemplazar `${nixProfileName}` por el nombre del perfil): sin eso, la evaluación falla.
8. **Tailnet:** si no incluye `services.headscale`, `services.caddy` (si se instaló con dominio) y `services.tailscale` con los mismos valores (sobre todo el mismo `server_url`, porque todos los dispositivos quedan registrados contra esa URL; en modo solo IP, también `address = "0.0.0.0"`), la tailnet se cae tras el reinicio de `connect-repo`. Los datos (`/var/lib/headscale`, `/var/lib/tailscale`) quedan en el disco, así que se recupera volviendo a declararla. Si copia `tailnet-key` o `tailnet-join`, tiene que definir `username`, `headscaleDomain` y `headscaleIp` (o reemplazarlos), igual que con `nixProfileName`. En las PCs alcanza con `services.tailscale.enable = true`: la sesión en la tailnet vive en `/var/lib/tailscale` y sobrevive al cambio de configuración (`connect-tailnet` no usa variables del `let`, así que se puede copiar tal cual).

Referencia: el historial (`93526f5`, `080c283`) muestra que el repo del autor para servidores es `git@github.com:mjb10/nixos-server` (probablemente privado; no está en este repo).

### 7.1 Contrato de `install-gpt-exo.sh`

Como instala con `nixos-install --flake` y no escribe `configuration.nix`, el flake tiene que cumplir con esto (los puntos 1, 4 y 6 de arriba siguen valiendo):

1. **Definir todo el sistema:**
   - los usuarios, mutables: el script no crea ninguno y solo pone la contraseña de root con `chpasswd`. También sus contraseñas iniciales o la forma de ponerlas;
   - SSH y sudo;
   - el firmware (`hardware.enableRedistributableFirmware`, para el Wi-Fi Realtek de la EXO);
   - el cargador de arranque (para la EXO, Limine con `BOOTIA32.EFI`, por el UEFI de 32 bits);
   - `stateVersion`;
   - el comando con que se actualiza (`update`): el script ya no instala `createKeys` ni `update`.

   Lo que falte no existe en el sistema instalado: no hay ninguna configuración intermedia.
2. **Importar el hardware** con `<hardware>` (el script pasa `-I hardware=/mnt/etc/nixos/hardware-configuration.nix`) o con `/etc/nixos/hardware-configuration.nix`. Durante la instalación, esa ruta absoluta se lee en el live, donde el script deja una copia.
3. **Leer `DISK` sin `/dev/`** (p. ej. `mmcblk1`), con `builtins.getEnv "DISK"`. Funciona porque el script usa `--impure`.
4. **Deploy key y URL:** si el `update` del flake usa la deploy key de `/root/.ssh/` y lee `/root/.github_repo_url`, el script se los deja en el sistema nuevo, en el mismo formato que dejaba `createKeys`.
5. **Substituters:** los que declare el sistema del flake (`nix.settings`) no se usan durante la instalación, porque rige el `nix.conf` del live. Lo que no esté en `cache.nixos.org` se compila en la EXO (por ejemplo, el Limine de 32 bits), y eso pesa en memoria (R6).

---

## 8. Convenciones y reglas de trabajo

### Paridad entre los 4 scripts (la regla más importante)

- Todo cambio que no sea específico de MBR/GPT o de VPS/PC se aplica **en los 4 scripts**.
- `install-gpt-exo.sh` **no** entra en la paridad ni en estos `diff`: es un script aparte (§2). Un cambio en los 4 no se copia ahí, ni al revés, salvo que el dueño lo pida.
- Para verificar la paridad después de editar (`diff` solo compara texto y no ejecuta nada de los scripts: es de lo poco que se puede correr en el host, §10.1):
  ```bash
  diff install-msdos.sh install-gpt.sh              # el particionado y el bloque de GRUB: BIOS vs UEFI (§2, punto 4)
  diff install-msdos.sh install-msdos-pc.sh         # diskName, swap, cargador de arranque, substituters, clear, espacios y la tailnet (§2)
  diff install-gpt.sh install-gpt-pc.sh             # ídem
  diff install-msdos-pc.sh install-gpt-pc.sh        # el particionado, el cargador de arranque y lo de §2, punto 7
  ```
  Contá las líneas con `diff a b | grep -c '^[<>]'` y comparalas con los valores de referencia de [`STATUS.md` §3](STATUS.md#3-paridad-actual): si da más sin un cambio intencional, se rompió la paridad. Entre VPS y PC la diferencia es grande a propósito (la tailnet y el cargador de arranque): ahí revisá a ojo que solo difieran las partes de §2.
- Si una diferencia nueva es intencional, explicala en §2 y actualizá el valor de referencia en `STATUS.md` §3.
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
  - `ab58750` dice *Remove duplicate terminal clear* pero **mueve** el `clear` al principio del script; `a64e250` vuelve a agregar otro antes de los prompts, así que hay dos (en PC, el segundo está comentado desde el 2026-11-22).
  - `f1fcd62` dice *Disable Tailscale connection* pero además **cambia GRUB por Limine** en `install-gpt-for-pc.sh`.
  - `9884e52` y `dda3702` dicen *Add installation scripts…* pero solo **renombran** scripts (y actualizan el README).
  - `b1967d6` dice *fix: update DISK variable documentation*, pero deja el comentario mal: dice *"e.g. sda"* y el valor es `/dev/sda`.
  - Los mensajes genéricos *"Update install-gpt-for-pc.sh"* (`12287c9`, `fbc27d9`) no dicen qué cambian: ver `CHANGELOG.md`.

### Documentación

- Todo cambio va en `CHANGELOG.md`, **arriba de todo** (§13).
- Si cambia el **estado** (algo se probó, apareció o se corrigió un problema o un riesgo, cambió la paridad, se decidió algo pendiente), actualizá `STATUS.md` en el mismo cambio.
- Si cambia algo visible para el usuario, actualizá `README.md`.
- Si cambia la **descripción** del proyecto (la estructura, el flujo, una mecánica, una convención o una decisión de diseño), actualizá este archivo, incluida la línea "Revisado el … contra el commit …" del encabezado.

---

## 9. Problemas conocidos, riesgos y estado: en `STATUS.md`

El estado del proyecto cambia casi tan seguido como el `CHANGELOG.md`, así que no vive en este archivo, sino en [`STATUS.md`](STATUS.md):

- qué script funciona y qué está probado (y con qué commit);
- qué falta probar y qué decisiones están pendientes;
- los valores de referencia de la paridad (§8);
- los problemas conocidos (**P1**, **P2**, …), los riesgos sin verificar (**R1**, **R2**, …) y los ya corregidos.

Los IDs `P…` y `R…` que aparecen en este archivo y en el `CHANGELOG.md` están definidos ahí, y nunca se renumeran ni se reutilizan. Leé `STATUS.md` antes de tocar los scripts, y actualizalo en el mismo cambio cuando algo se pruebe, se rompa o se corrija (sus reglas están en su §7).

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
| Ejecutar los comandos del sistema instalado: `connect-repo`, `createKeys`, `update`, `tailnet-key`, `connect-tailnet`, `headscale`, `tailscale up` o las líneas de §3 Fase 3 (`nixos-generate-config`, `nixos-rebuild`, `reboot`) | ❌ Nunca: son para el VPS o la PC recién instalados |

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

- **Por qué es seguro:** los comandos corren dentro del sandbox de builds de Nix, con un usuario sin privilegios (`nixbld`), sin red, sin `sudo`, sin acceso a tu `$HOME` ni a los discos (el `/dev` del sandbox no tiene dispositivos de bloque). Solo ven una copia de solo lectura de los `install-*.sh` (hoy cinco, con `install-gpt-exo.sh`) en `/nix/store`: el `filter` deja afuera todo lo demás, para que ningún otro archivo de la carpeta (por ejemplo, algo sin commitear con datos privados) termine en el store, que es legible por todos los usuarios. En el host solo quedan esa copia y un archivo de texto con el resultado. Como `--no-out-link` no crea raíces de GC, el próximo garbage collection normal los elimina: no hace falta correr nada.
- **Requisito:** el sandbox de Nix tiene que estar activado. En NixOS viene así por defecto; comprobalo con `grep '^sandbox' /etc/nix/nix.conf` (debe decir `true`). Si dice `false`, **no** uses este método.
- `<nixpkgs>` tiene que resolver: `nix-instantiate --find-file nixpkgs` debe devolver una ruta.
- `bash -n` revisa **un solo archivo por invocación** (con `bash -n a.sh b.sh`, `b.sh` se toma como argumento de `a.sh` y no se revisa); por eso el `for`.
- `shellcheck` va a marcar P5 y otros detalles: es esperable. Referencia: al `a64e250` los 4 scripts pasan `bash -n`. Al 2026-11-26, con los cambios sin commitear, pasan los 5. En `install-gpt-exo.sh`, `shellcheck` solo marca los `/dev/$diskName` sin comillas de los `parted` (como en los otros) y dos falsos positivos: `passwordRoot`, que se asigna con `printf -v`, y el `'$branch'` del mensaje de error, que sí se expande.
- Además de `bash -n` y `shellcheck`, en el mismo sandbox se pueden probar **pedazos del script que no tocan discos** (validaciones, armado de URLs, nombres de partición), tomándolos del archivo real con `sed`/`grep` y corriéndolos con valores de ejemplo. Se pasa el script de prueba como otra entrada del `runCommand` (`tests = builtins.path { … }`) y se ejecuta con `bash $tests` después del `shellcheck`. Así se hizo el 2026-11-26 con `install-gpt-exo.sh`: 43 chequeos, todos OK (`STATUS.md` §1). Nunca se prueban así comandos de disco (`parted`, `wipefs`, `mkfs`, `mount`) ni nada que necesite root o red.
- Ni `bash -n` ni `shellcheck` validan el Nix de adentro de los heredocs: eso se valida en la VM (§10.3).

Alternativa sin Nix (otra máquina): un contenedor **rootless**, sin red y con el repo montado en solo lectura:

```bash
podman run --rm --network=none -v "$PWD":/src:ro -w /src docker.io/library/bash:5 \
  bash -c 'for f in install-*.sh; do bash -n "$f" && echo "bash -n OK: $f"; done'
podman run --rm --network=none -v "$PWD":/src:ro -w /src docker.io/koalaman/shellcheck:stable \
  install-gpt-exo.sh install-gpt-pc.sh install-gpt.sh install-msdos-pc.sh install-msdos.sh
```

Nunca uses `--privileged`, `--device` ni montes `/dev` o discos del host. Preferí `podman` rootless: Docker con el grupo `docker` equivale a root en el host.

### 10.3 Prueba real: solo en una VM descartable

Lo único que prueba el comportamiento de verdad (particionado, el Nix generado, `nixos-install`, `connect-repo`/`update`) es una instalación completa, y se hace **solo** en una máquina virtual que se pueda borrar.

- **Disco:** una imagen de disco nueva y vacía (p. ej. qcow2), creada para la prueba. Nunca le pases a la VM un disco, una partición o un volumen real del host (`/dev/sdX`, `/dev/nvme…`, LVM), ni passthrough de controladoras USB/PCI: el script lo borraría. Los scripts de VPS usan `/dev/vda` fijo, así que el disco de la VM tiene que ser virtio.
- **Sin carpetas compartidas** con el host (virtiofs, 9p): dentro de la VM los scripts corren como root.
- **ISO y firmware:** el ISO de NixOS que coincida con `stateVersion` (R4). BIOS para los scripts MSDOS; UEFI (OVMF) para los GPT. Qué probar primero: `STATUS.md` §2. En los scripts de PC conviene probar también con un disco SATA (`sda`) y no solo virtio: con `vda`, un `/dev/vda` copiado por error de los scripts de VPS funcionaría por casualidad.
- **Dónde se ejecuta:** el `curl … | bash` (o la URL raw de una rama de prueba, §8) se escribe **en la consola de la VM**. Antes de pegarlo, confirmá que la ventana activa es la de la VM y no una terminal del host. En los scripts de PC, el disco que se ingresa es el de la VM (verificalo con `lsblk` dentro de la VM).
- **El Nix generado se valida acá:** si `nixos-install` termina sin errores, el `configuration.nix` evaluó y se construyó.
- **`connect-repo`/`update`:** se prueban dentro de la VM ya instalada, con un repo de prueba o con una deploy key que después borres de GitHub.
- **Al terminar:** borrá la VM, su imagen de disco y las deploy keys de prueba que hayas cargado en GitHub.
- **Agentes de IA:** no creen ni arranquen VMs por su cuenta. Denle los pasos al usuario o, si los pide, muéstrenle antes el comando exacto.

---

## 11. Decisiones de diseño (no revertir sin motivo)

| Decisión | Commit | Motivo |
|---|---|---|
| Dos heredocs (interpolado + literal) | `a9f0198`, `c3cb08a`, `0198bc8` | Interpolar `$username`/`$diskName` sin romper el código shell de `createKeys`/`update` (§6.3). Desde `0198bc8` el bloque 1 es solo un `let` y el resto usa variables de Nix. |
| `createKeys` y `update` como `writeShellScriptBin` en vez de alias | `da9847c` | Los alias con `bash -c '…'` y comillas anidadas eran frágiles; los binarios se pueden llamar entre sí. |
| `/root/.ssh/config` con `echo -e … \| sudo tee` | `30cab0b` | El heredoc anidado cerraba el heredoc externo (§6.3). |
| `sudo` por comando dentro de `createKeys` | `c22a15f`, `262276f` | `sudo -i` dentro de un script no eleva los comandos siguientes (§6.6). |
| Contraseña del usuario con `chpasswd -R /mnt` | `ae8759d` | `nixos-enter` + `passwd` no funcionaba de forma no interactiva. |
| Lectura desde `/dev/tty` | `7fb73bd` | stdin es el script (§6.2). |
| URL `:` → `/` | `da9847c` | Pasar de formato scp a una URL `git+ssh://` válida. |
| `nixos-rebuild boot` + `reboot` | `77cab70` | §6.5. |
| Reiniciar solo si `update` terminó bien | `76fe019` | Si falla el build, no mostrar un "completada" falso ni reiniciar con la configuración del instalador: el error queda en pantalla. |
| Rama opcional en `update` (`?ref=` solo si se ingresa, antes del `#<perfil>`) | `76fe019` | Poder construir desde otra rama sin perder la rama por defecto; la query tiene que ir antes del fragmento (§6.7). |
| Tailnet propia: headscale detrás de Caddy, en `127.0.0.1:8080` | `efdcedd` | Caddy saca y renueva el certificado HTTPS solo, sin pedir email (con `security.acme` de NixOS habría que poner uno, y sería un dato personal en el repo). La máquina se une a su tailnet por `http://127.0.0.1:8080`, que funciona en los dos modos aunque el certificado todavía no exista. |
| Modo solo IP (dominio vacío): headscale por HTTP en `0.0.0.0:8080`, sin Caddy | `efdcedd` | Pedido del dueño, para usar headscale sin dominio. Es la alternativa no recomendada (riesgos en §3, Fase 2b); el instalador lo avisa. En el `let` se guardan solo los valores ingresados (`headscaleDomain`, `headscaleIp`) y la URL se arma en el bloque 2. |
| La máquina se une a su tailnet sola (`tailnet-join`), con una pre-auth key creada en el momento | `efdcedd` | Pedido del dueño: el servidor tiene que quedar como nodo de la tailnet sin pasos manuales. La clave se genera y se usa en la misma máquina (un solo uso, 10 minutos): no se muestra, no se guarda y no pasa por el instalador. |
| Servidor headscale solo en los scripts de VPS; las PCs son clientes con `connect-tailnet` | `efdcedd` (VPS), `856fe37` (`connect-tailnet`; comentado en `install-gpt-pc.sh` desde `f1fcd62`) | Decisión del dueño: el servidor de coordinación va en el VPS (IP pública, siempre encendido). `connect-tailnet` sigue el estilo de `connect-repo` (se corre después del primer arranque) y la clave no se guarda en disco ni se pide durante la instalación, donde podría vencer antes del primer arranque. |
| Disco al flake como variable de entorno `DISK` (en los 4 scripts) | `5bc319e` (PC), `efdcedd` (VPS) | Llega como string con `builtins.getEnv "DISK"`, se interpola sin riesgo y no rompe la evaluación si falta (§7). |
| `tailnet-key` para sumar otros dispositivos | `efdcedd` | Generar una clave de un solo uso y el comando exacto para el dispositivo nuevo, sin tener que recordar la CLI de headscale (en la 0.29, `preauthkeys create --user` pide el ID numérico del usuario, no el nombre). |
| Deploy key sin passphrase (`-N ""`) | `6d2bf39` | Que `nixos-rebuild` como root pueda clonar sin intervención. |
| `PermitRootLogin = "no"` | `3b8644c` | Se probó `"yes"` (`4fa0101`) y se volvió a `"no"`; se entra con el usuario creado. |
| Usuario elegido al instalar (antes fijo: `nixi`) | `fdf1bc5`, `b83b24e` | Reutilizar los scripts con cualquier usuario. |
| Salida de particionado visible | `2315432` → `dd212b7` | Se ocultó y se revirtió a los 3 minutos: ver la salida ayuda a detectar errores (no hay manejo de errores, P5). |
| `configuration.nix` mínimo | `183c8b6`, `3b8644c` | Solo lo necesario para el primer acceso; el resto va en el flake. |
| `clear` antes de los prompts de usuarios | `dd212b7`, `a64e250` | Que los prompts de contraseñas no queden mezclados con la salida de `parted`/`mkfs`. En los de PC está comentado desde `e6718da`/`12287c9` (los commits no dicen por qué). |
| Cargador según la tabla de particiones: GRUB solo BIOS en los MSDOS, GRUB solo UEFI (`nodev`) en `install-gpt.sh`, Limine solo en `install-gpt-pc.sh` | sin commitear (2026-11-25), después de `f35753d` | Decisión del dueño. Limine solo lee particiones FAT, y los MSDOS no tienen ninguna; GRUB solo BIOS es la configuración que funcionó en Upcloud. En GPT sin partición `bios_grub`, GRUB solo puede instalarse para UEFI (P2). Los commits que pasaron `install-gpt-pc.sh` a Limine (`f1fcd62`, `f35753d`) no dicen el motivo. |
| `parted -s` y `mkfs.ext4 -F` | `dad977e`, `f35753d`, `479bf18` | Que no pidan confirmación: leerían la respuesta de stdin, que es el propio script (§6.2, R3). |
| `install-gpt-exo.sh` como script aparte, fuera de la paridad | `8a2a71f` | Hardware distinto (eMMC, UEFI de 32 bits, 2 GB de RAM) y un flujo propio. |
| `install-gpt-exo.sh` instala con `nixos-install --flake`, sin `configuration.nix` intermedio | sin commitear (2026-11-26) | Pedido del dueño: que la primera generación ya sea la del repo y no ocupe espacio de más (con el camino viejo, ~11 GB de basura después de `connect-repo`). Para lo mismo: `--no-channel-copy`, cachés de Nix en `/mnt` (los 2 GB de RAM del live) y `nix-collect-garbage` antes de apagar. |
| Deploy key y comprobación del repo (`git ls-remote`) antes de borrar | sin commitear (2026-11-26) | Que una URL, una rama o una clave mal puestas aparezcan antes de tocar los discos. Es lo que hacía `connect-repo`, ahora dentro del instalador. |
| El script de la EXO no crea usuarios | sin commitear (2026-11-26) | Decisión del dueño: los usuarios (mutables) salen del flake; el script solo pone la contraseña de root. |
| Swap temporal (4 GiB en `ec0d9a4`, 8 GiB sin commitear), `vm.swappiness=150`, `vm.min_free_kbytes=65536` y `ulimit -c 0` durante `nixos-install` en `install-gpt-exo.sh` | `ec0d9a4`, sin commitear (2026-11-27) | Kernel panic en la EXO al evaluar el flake (P14). Se usa un archivo temporal y no una partición de swap más grande: funciona también al seguir una corrida anterior, sin borrar el disco, y no le quita lugar a la eMMC después de instalar. La swap del sistema instalado la define el flake. |
| Volver a correr `install-gpt-exo.sh` sigue la instalación anterior (`has_install_layout`, `format_part`), con `ERASE` para empezar de cero | `68cf7ff` | Pedido del dueño, después de P13: que una corrida cortada por un error no obligue a borrar y particionar de nuevo. Se detecta por el estado del disco (los nombres de las particiones y `blkid`), no por un archivo de estado: sirve también después de reiniciar el live. `nixos-install` se vuelve a correr siempre, porque reutiliza lo que ya hizo y saltearlo podría dejar el sistema sin cargador de arranque (el perfil `system` existe antes de instalarlo). |
| Borrar los discos antes de particionar (`release_disk`, `wipe_disk`) | sin commitear (2026-11-26) | Pedido del dueño: en la EXO, `cfdisk` sin argumentos solo abre la USB del instalador, y la eMMC viene con Windows. Además libera lo que dejó montado una corrida anterior en la misma sesión. |
| Discos extra como ext4 vacío para archivos, sin montar (`files_disk`) | sin commitear (2026-11-26) | Pedido del dueño, para la microSD. El formato ext4 lo eligió él, y montarla sola quedó descartado. La raíz es `root:users` con modo `2775` porque el script no crea usuarios: así puede escribir cualquier usuario normal del flake. |

---

## 12. Historia en breve

El desarrollo empezó el 2026-11-05: 72 commits al `b4f632f` (2026-11-07), 98 al `479bf18` (2026-11-25) y 109 al `9bbd37d` (2026-11-26). Detalle en `CHANGELOG.md`.

1. **2026-11-05, mañana:** `install-mbr.sh` inicial con usuario fijo `nixi` y un `configuration.nix` completo (con comentarios por defecto, `fail2ban`, `btop`). Se agregan `createKeys` (deploy key) y un alias `update` con `bash -c` y `nixos-rebuild switch`.
2. **2026-11-05, mediodía:** `install-gpt.sh` (con `systemd-boot`), README con los comandos `curl`.
3. **2026-11-05, tarde:** muchas iteraciones para las contraseñas (`read -s`, `nixos-enter`, `/dev/tty`, `chpasswd`), `sudo` por comando, limpieza del `configuration.nix`, sudo sin contraseña. GPT pasa a GRUB (origen de P2).
4. **2026-11-05, noche:** `update` como binario, URL `:` → `/`, `boot` en vez de `switch`, arreglo del heredoc anidado.
5. **2026-11-06, mañana:** usuario elegido al instalar, división en dos heredocs, opciones `ssh` del README, scripts para PC, rediseño del README.
6. **2026-11-06, media mañana–tarde:** paridad total entre los 4 scripts, limpieza (sin `fail2ban`/`btop`/alias extra, `PermitRootLogin = "no"`), salida visible, `clear`, README con opciones y pasos numerados.
7. **2026-11-07:** reubicación del `clear` (desde ahí hay dos), esta documentación (`AGENTS.md`, `CHANGELOG.md`, `CLAUDE.md`) y el título *"(Opción 2)"* de GPT en la sección de PCs del README.
8. **2026-11-09 a 2026-11-11:** perfil de Nix elegido al instalar, el bloque 1 del heredoc pasa a ser solo un `let`, rama opcional en `update` y reinicio solo si `update` termina bien.
9. **2026-11-18 y 2026-11-19:** `tailscale` en los 4, el disco al flake como `DISK`, headscale en los de VPS (servidor) y `connect-tailnet` en los de PC (clientes).
10. **2026-11-20 a 2026-11-23:** GRUB con `efiSupport` en los 4. En `install-gpt-for-pc.sh`, una serie de pruebas: ESP de 1 GB, una partición `bios_grub` (agregada y después comentada), `parted -s` y el paso a Limine (con `tailscale` y `connect-tailnet` comentados). En PC se comenta el segundo `clear`.
11. **2026-11-25:** Limine en los 4, renombre de los scripts (`mbr` → `msdos`, `-for-pc` → `-pc`), `parted -s` y `mkfs.ext4 -F` en los 4, y vuelta a GRUB en todos menos `install-gpt-pc.sh` (solo BIOS en los MSDOS, solo UEFI en `install-gpt.sh`; `8c5b808`, junto con el nuevo `STATUS.md`). Después: el segundo `clear` comentado también en VPS, y en `install-gpt-pc.sh` la partición BIOS activa y Limine de 32 bits (`BOOTIA32.EFI`). Nace `install-gpt-exo.sh` para la EXO Wings K1322 (detección del disco, confirmación, preguntas antes de borrar) y se ajusta su particionado varias veces esa noche.
12. **2026-11-26:** en `install-gpt-exo.sh` (sin commitear): borrado de los discos antes de particionar, microSD como disco ext4 para archivos, corrección del solapamiento de particiones (P12) e instalación directa desde el flake (`nixos-install --flake`), con la deploy key y el repo comprobados antes de borrar. El script deja de escribir `configuration.nix` y de crear usuarios.

---

## 13. Mantenimiento de `CHANGELOG.md`

- Orden **cronológico inverso**: lo más nuevo arriba de todo; hacia abajo, lo más viejo. Lo mismo dentro de cada día.
- Una sección por día (`## AAAA-MM-DD`), en hora de Argentina (UTC−03:00), igual que los commits del autor. Usá la fecha real del cambio (`git log --date=iso`), nunca una inventada.
- Si ya existe la sección del día, agregá la entrada **arriba** dentro de esa sección.
- Cada entrada empieza con el hash corto del commit entre backticks y un prefijo de área (`Scripts`, `README`, `Docs`). Si el cambio todavía no está commiteado, usá **(sin commitear)** en lugar del hash y reemplazalo por el hash después de commitear.
- Describí lo que cambió **en el código**, no copies el mensaje del commit si no coincide con el diff (marcalo con ⚠️).
- Si el cambio afecta el estado (un problema corregido, algo probado), va además en `STATUS.md`, en el mismo commit. Las reglas de ese archivo están en su §7.

---

## 14. Checklist para cualquier cambio

1. ¿El cambio aplica a los 4 scripts? Aplicalo en los 4 y corré los `diff` de paridad (§8). `install-gpt-exo.sh` va aparte: solo se toca si el cambio es para él.
2. ¿Agregaste un prompt? `read -rp … < /dev/tty` (§6.2).
3. ¿Tocaste el `configuration.nix`? Variables de instalación → `let` del bloque 1, y en el bloque 2 se usan como variables de Nix (`${username}`, nunca `$username`); todo lo demás, incluido el código de `createKeys`/`update` → bloque 2; ninguna línea igual a `EOF`; llaves balanceadas; nada de `${…}` dentro de `'' … ''` (§6.3, §6.4).
4. Chequeos estáticos (`bash -n` y `shellcheck`) **solo** en el sandbox de Nix o en un contenedor sin red (§10.2), nunca en el host. Si el cambio altera el comportamiento, probalo en una VM descartable (§10.3).
5. `CHANGELOG.md` arriba de todo; `STATUS.md` si cambia el estado (probado, problemas, riesgos, paridad); `README.md` si cambia algo visible; este archivo solo si cambia la descripción del proyecto (flujo, estructura, mecánicas, convenciones, decisiones).
6. Commit en inglés, imperativo. Para cambios no triviales, rama + prueba en VM antes de `main` (§8, §10).
