# STATUS.md — nixos-first-install

> Estado actual del proyecto: qué script funciona, qué está probado, qué falta probar, problemas conocidos (P), riesgos sin verificar (R) y correcciones.
> Cambia casi tan seguido como [`CHANGELOG.md`](CHANGELOG.md): actualizalo **en el mismo cambio** que lo afecta (§7).
> Para entender el proyecto (flujo, mecánicas, convenciones, decisiones): [`AGENTS.md`](AGENTS.md). Historial commit por commit: [`CHANGELOG.md`](CHANGELOG.md).
> **Actualizado al 2026-11-26** contra el commit **`9bbd37d`** más los cambios sin commitear de `install-gpt-exo.sh` (borrado previo de discos, microSD para archivos e instalación desde el flake; ver `CHANGELOG.md`). Si `git log -1` muestra otro commit, revisá lo que cambió después antes de confiar en este archivo.

---

## 1. Estado por script

| Script | Cargador de arranque | Última prueba real | Estado |
|---|---|---|---|
| `install-msdos.sh` (VPS) | GRUB solo BIOS, en `/dev/vda` | Funcionó en Upcloud como `install-mbr.sh` (confirmado al 2026-11-07, `a64e250`), con la misma configuración de GRUB que tiene hoy. | Debería funcionar, pero la versión actual no está probada: desde aquella prueba se agregaron la tailnet, `DISK`, `parted -s` y `mkfs.ext4 -F`. |
| `install-gpt.sh` (VPS) | GRUB solo UEFI (`device = "nodev"`) | Nunca. | Debería arrancar en una máquina UEFI desde que se corrigió P2 (`8c5b808`). |
| `install-msdos-pc.sh` (PC) | GRUB solo BIOS, en `/dev/${diskName}` | Nunca. | Debería funcionar desde que se corrigió P11 (`8c5b808`). No sirve para discos NVMe/eMMC (P6). |
| `install-gpt-pc.sh` (PC) | Limine (UEFI de 64 y de 32 bits con `BOOTIA32.EFI` desde `c8d9216`, y BIOS) | Nunca. | Por UEFI debería arrancar (ESP FAT montada en `/boot`); por BIOS no está verificado (R5). `connect-tailnet` está desactivado (§2). No sirve para discos NVMe/eMMC (P6). |
| `install-gpt-exo.sh` (EXO Wings K1322; también se usa en PCs con `sda`) | El que defina el flake: el script ya no escribe configuración (para la EXO, Limine con `BOOTIA32.EFI`) | Sin resultado anotado. El dueño lo prueba en la EXO y en PCs con `sda`. | La versión actual (sin commitear) instala directamente desde el repo del flake y no está probada. Chequeo estático del 2026-11-26 en el sandbox de Nix: `bash -n` y `shellcheck` sin problemas nuevos, y 43 chequeos de su lógica (URL y rama, URL del flake, nombres de partición, "disco en uso", mensajes, `read` desde `/dev/tty`, `< /dev/null`), todos OK. Riesgos: R6 y R7. |

**Sin probar en VM** (según `CHANGELOG.md`): la tailnet en VPS (headscale, Caddy, `tailnet-join`, `tailnet-key`: `efdcedd`), el disco al flake como `DISK` (`5bc319e`, `efdcedd`), `connect-tailnet` (`856fe37`), los cargadores de arranque actuales (2026-11-25) y todo `install-gpt-exo.sh` (2026-11-26).

Problemas abiertos que afectan a los 4 scripts: P1 (contraseña de root), P4 (contraseñas visibles), P5 (sin manejo de errores), P7 (entradas sin validar), P8 (comentarios) y P9 (grupo `docker`). Detalle en §4, que también dice cuáles aplican a `install-gpt-exo.sh`.

---

## 2. Pendientes

### Qué probar primero

Cómo probar sin riesgo: [`AGENTS.md` §10.3](AGENTS.md#103-prueba-real-solo-en-una-vm-descartable) (solo en una VM descartable, nunca en el host).

1. **`install-msdos.sh`** en una VM BIOS con disco virtio: es el que se usa en Upcloud, y `main` es lo que baja el próximo `curl`. Probarlo antes de reinstalar un VPS.
2. **`install-gpt.sh`** en una VM UEFI (OVMF): GRUB solo UEFI es nuevo.
3. **`install-gpt-pc.sh`** en una VM UEFI y en una BIOS (R5).
4. **`install-msdos-pc.sh`** en una VM BIOS con disco SATA (`sda`), no solo virtio: con `vda`, un `/dev/vda` copiado por error de los scripts de VPS funcionaría por casualidad.
5. **Tailnet:** `tailnet-join` y `tailnet-key` en una VM de VPS, y `connect-tailnet` desde una VM de PC instalada con `install-msdos-pc.sh`.
6. **`install-gpt-exo.sh`** en una VM UEFI (OVMF), antes de la EXO real. Hace falta:
   - un repo de prueba con un flake que defina todo el sistema (§7.1 de `AGENTS.md`), y cargar en GitHub la deploy key que muestra el script (después, borrarla);
   - un disco virtio de al menos ~20 GB: la detección elige el único candidato;
   - para probar la microSD, una tarjeta SD emulada (`-device sdhci-pci -device sd-card,drive=…`), que aparece como `mmcblk` de tipo `SD`.

   Qué revisar:
   - que `git ls-remote` frene una URL, una rama o una clave mal puestas antes de borrar;
   - que el reintento de `nixos-install` funcione con un perfil mal escrito;
   - que las cachés vayan a `/mnt` (R6);
   - que el sistema arranque con la configuración del flake y que `update` funcione con la clave copiada;
   - el espacio en el store después de `nix-collect-garbage`, comparado con los ~11 GB del camino viejo.

   El arranque con UEFI de 32 bits (`BOOTIA32.EFI`) solo se prueba en la EXO real.

### Decisiones pendientes del dueño

- `tailscale` y `connect-tailnet` están comentados en `install-gpt-pc.sh` desde `f1fcd62`, pero no en `install-msdos-pc.sh`. No consta si es temporal. Mientras tanto, una PC GPT se suma a la tailnet con el `sudo tailscale up …` que muestra `tailnet-key` (el comando `tailscale` existe igual, porque lo agrega `services.tailscale`).

---

## 3. Paridad actual

Valores de referencia para los `diff` de [`AGENTS.md` §8](AGENTS.md#8-convenciones-y-reglas-de-trabajo). Si un `diff … | grep -c '^[<>]'` da más que esto sin un cambio intencional, se rompió la paridad. Cada diferencia intencional nueva actualiza esta tabla y se explica en `AGENTS.md` §2.

| Comparación | Líneas | Qué explica la diferencia |
|---|---|---|
| `install-msdos.sh` vs `install-gpt.sh` | **26** | El particionado (18 líneas, como al `a64e250`), 2 líneas de espacios de `76fe019` y 6 del bloque de GRUB (`device` y las 2 líneas de EFI, comentadas en MSDOS). |
| `install-msdos-pc.sh` vs `install-gpt-pc.sh` | **86** | El particionado (con la partición BIOS activa en GPT desde `f50b589`), GRUB vs Limine (con el Limine de 32 bits de `c8d9216`), `tailscale` y `connect-tailnet` comentados en GPT y el `echo ""` de más de `76fe019`. |
| VPS vs PC (`install-msdos.sh` vs `install-msdos-pc.sh`, `install-gpt.sh` vs `install-gpt-pc.sh`) | 194 y 222 | Grande a propósito: la tailnet, el disco, la swap, los substituters y, en GPT, la partición BIOS y el Limine de PC. El segundo `clear` ya no difiere: está comentado en los 4 desde `69961bf`. Revisar a ojo que solo difieran las partes de `AGENTS.md` §2. |

`install-gpt-exo.sh` no entra en la paridad: es un script aparte, con su propio flujo (`AGENTS.md` §2 y §3).

Historia: 18 líneas al `a64e250` (2026-11-07), 20 al 2026-11-19 (entre `install-mbr.sh` e `install-gpt.sh`); 79, 196 y 219 al 2026-11-25 (`8c5b808`), antes de `69961bf`, `f50b589` y `c8d9216`.

---

## 4. Problemas conocidos (abiertos)

Detectados leyendo el código: la mayoría al 2026-11-07 (`a64e250`), revisados al 2026-11-25. **No están corregidos.** No los arregles sin que el usuario lo pida, pero tenelos en cuenta. Los arreglos sugeridos (acá y en §5) son cambios **al texto de los scripts**, no comandos para ejecutar en el host.

**En `install-gpt-exo.sh`** (revisado al 2026-11-26):
- **No aplican:** P1 (root se pone con `chpasswd` desde `fe9728a`), P3 y P9 (no escribe `configuration.nix`), P6 (usa `p` en eMMC/NVMe) ni la parte de P7 sobre `username` (no crea usuarios).
- **Aplican:** P4 (la contraseña de root se ve, aunque se pide dos veces) y P5 en parte. Cortan con error el borrado, la microSD, `nixos-install` (con reintento), la contraseña y la copia de la clave. En cambio, `parted`, `mkfs` y `mount` siguen sin chequeo.
- **P7 en parte:** la URL del repo y la rama se comprueban con `git ls-remote` antes de borrar, pero el perfil no se valida. Si no existe en el flake, falla `nixos-install`, que se puede reintentar con otro.

| ID | Problema | Dónde | Detalle / arreglo sugerido |
|---|---|---|---|
| P1 | **La contraseña de root nunca se establece** | 4 scripts, `echo "$passwordRoot" \| nixos-install` | `nixos-install` solo pide la contraseña de root si stdin es una terminal (`if [[ -z $noRootPasswd ]] && [ -t 0 ]`, verificado en el código de `nixos-install`). Con un pipe se saltea ese paso y root queda sin contraseña (bloqueado). El acceso funciona igual por el usuario con sudo. Arreglo: `nixos-install --no-root-passwd` y después `echo "root:$passwordRoot" \| chpasswd -R /mnt`. |
| P3 | El cache `nix-community.cachix.org` no se usa | scripts de VPS, `nix.settings` (en PC está comentado desde `f35753d`) | Se agrega a `substituters` pero sin su clave en `trusted-public-keys`, así que Nix rechaza esos binarios. Agregar la clave pública que publica nix-community.cachix.org o quitar el substituter, como en PC. |
| P4 | Las contraseñas se ven en pantalla | 4 scripts, prompts | `read -rp` sin `-s` y sin confirmación. El `-s` existía (`da5a8f7`) y se perdió al pasar a `/dev/tty` (`7fb73bd`). |
| P5 | Sin manejo de errores | 4 scripts | No hay `set -euo pipefail`: si falla `parted`/`mkfs`/`mount`/`nixos-install`, el script sigue igual y termina en `poweroff`. (Lo único que revisa un resultado es `createKeys`, que no reinicia si `update` falla.) |
| P6 | Nombres de partición incompatibles con NVMe/eMMC | scripts PC | `/dev/$diskName"1"` da `nvme0n1` + `1` = `nvme0n11` en vez de `nvme0n1p1`. |
| P7 | Entradas sin validar | 4 scripts + `createKeys`/`update` | `username` vacío o con caracteres raros (p. ej. `.`, `"`) rompe el `let` o `users.users.${username}` en Nix. `diskName` no se verifica antes de borrar el disco. Un `nixProfile` con `"`, `\` o `${` rompe el `configuration.nix` (y `nixos-install` falla); si no coincide con ningún `nixosConfigurations.<perfil>` del flake, falla `update`. La URL del repo solo funciona en formato scp (`git@github.com:usuario/repo.git`): una URL HTTPS o `ssh://…:22/…` queda mal porque se reemplazan **todos** los `:`. La rama que pide `update` tampoco se valida: si no existe en el repo, falla el fetch, y un nombre con caracteres que significan algo en una URL (`#`, `&`, `%`) arma una URL inválida. En VPS, `headscaleDomain` no se valida (solo se le sacan `http://`, `https://` y la `/` final): un dominio que no apunta a la máquina deja a Caddy sin certificado (la máquina se une igual a su tailnet, pero los demás dispositivos no pueden conectarse); una IP o un `host:puerto` escritos ahí no activan el modo solo IP, sino que arman un `https://…` que no funciona; y uno con `"` o `${` rompe el `configuration.nix`. `headscaleIp` tampoco se valida (solo que no quede vacía): si la detección falla o la máquina está detrás de NAT, hay que escribir la IP pública a mano. Para headscale, el usuario de Linux además tiene que tener al menos 2 caracteres y empezar con una letra; si no, `tailnet-join` y `tailnet-key` fallan al crear el usuario de headscale. En PC, `connect-tailnet` solo verifica que la URL y la clave no estén vacías: una URL mal escrita la detecta `tailscale up` (falla o vence el `--timeout 2m`). |
| P8 | Comentarios desactualizados o engañosos | 4 scripts | *"here a 8GB one is created"* (la swap es de 1 GB o 2 GB); la ESP dice *512MiB* pero se crea con `512MB`; el primer `clear` (antes de `sudo -i`) tiene el comentario *"before proceeding with user setup"*, que solo es cierto para el segundo; *"Installation of NixOS and setting 'root' password"* (no se aplica, P1). En PC, el comentario de `DISK` en `update` dice *"e.g. sda"*, pero el valor es la ruta completa (`/dev/sda`, desde `b1967d6`), y en `install-gpt-pc.sh` el de la ESP dice *512MiB* pero se crea de `2MB` a `1024MB` (desde `f50b589`). Cosmético: las líneas `tmp.cleanOnBoot` y, en `install-gpt-pc.sh`, `biosSupport` están indentadas con tabs. |
| P9 | Grupo `docker` sin Docker | 4 scripts | `extraGroups` incluye `docker` pero Docker no se habilita (se espera del flake). |
| P10 | README desactualizado o incompleto | `README.md` | El paso 3 dice *"con usuario 'nixi'"* (el usuario se elige al instalar desde `fdf1bc5`/`b83b24e`); la sección de PCs no explica los pasos posteriores (`connect-repo` también existe en PC); no advierte que los scripts borran el disco sin preguntar ni que solo deben correrse desde el ISO live. (El *"(Opción 1)"* repetido en PCs se corrigió en `b4f632f`.) |

---

## 5. Riesgos sin verificar

Hay que comprobarlos en una VM antes de darlos por ciertos.

| ID | Riesgo |
|---|---|
| R1 | `createKeys` escribe `/root/.ssh/config` **antes** de que exista `/root/.ssh` (lo crea recién `ssh-keygen`). En un sistema limpio el `tee` podría fallar, y `git+ssh` no usaría la deploy key (en un segundo intento sí, porque el directorio ya existe). Mitigación posible: `sudo mkdir -p -m 700 /root/.ssh` al principio. |
| R2 | Ejecutar `connect-repo` por segunda vez: `ssh-keygen` pregunta si sobrescribir la clave, pero su salida va a `/dev/null`, así que parece colgado. |
| R4 | `system.stateVersion = "26.11"` está fijo. Al 2026-11-07 la estable es **26.05** y 26.11 es *unstable* (sin release todavía), así que el valor coincide con un ISO unstable. Si se instala con el ISO estable, debería ser `"26.05"`. Revisarlo cada vez que se cambie de ISO. |
| R5 | `install-gpt-pc.sh` usa Limine con `biosSupport = true` en un disco GPT. Desde `f50b589` hay una partición 4 `bios_grub` (`1MiB`–`2MiB`), pero no se define `partitionIndex`, así que no está verificado que `limine bios-install` la use, ni que pueda instalarse sin ella. El instalador de NixOS no revisa su resultado (`subprocess.run` sin `check`), así que si falla no se nota durante la instalación. Por UEFI debería arrancar igual: la ESP FAT está montada en `/boot`. |
| R6 | `install-gpt-exo.sh` evalúa y construye todo el sistema del flake durante la instalación, en el live de la EXO, con 2 GB de RAM. Mitigaciones: las cachés de Nix van a `/mnt` (`XDG_CACHE_HOME`), los temporales también (`nixos-install` pone `TMPDIR` en `/mnt`), la swap de 2 GB del disco ya está activa y `--max-jobs 1`. Pero la evaluación de nixpkgs y las compilaciones locales (Limine de 32 bits, labwc, wvkbd) corren en memoria, y la copia del repo que baja `nix flake metadata` va al store del live, que está en RAM. No está verificado que alcance. Si se queda sin memoria, `nixos-install` falla y se puede reintentar sin volver a particionar. |
| R7 | Las opciones que usa `install-gpt-exo.sh` (`--flake`, `--impure`, `-I`, `--no-channel-copy`, `--no-root-passwd`, `--max-jobs`) y que `nixos-install` pone `TMPDIR` en `/mnt` se verificaron en el código del `nixos-install` del host, no en el del ISO. Si el ISO tiene otra versión, podría diferir (por ejemplo, `--refresh` no se acepta y por eso no se usa). |

---

## 6. Corregidos

Lo más nuevo arriba. El detalle de cada cambio está en `CHANGELOG.md`.

| ID | Qué era | Corrección |
|---|---|---|
| P12 | En `install-gpt-exo.sh`, la partición BIOS (`512MiB`–`1024MiB`, de `9bbd37d`) se superponía unos 47 MiB con root, que arrancaba en `1024MB` (976,6 MiB). `parted -s` no podía crear la partición 4 y el `set 4 bios_grub on` fallaba. Antes, en `83b05b6`, la BIOS (`1MiB`–`2MiB`) se superponía con la ESP (`1MB`–`1024MB`), y lo arregló `67eca32`. | 2026-11-26, sin commitear: root arranca en `1024MiB`. |
| P2 | `install-gpt.sh` pedía instalar GRUB en modo BIOS en un disco GPT. Con `device = "/dev/vda"`, NixOS instala primero la parte BIOS y después la EFI, y aborta si cualquiera falla (verificado en `install-grub.pl` de nixpkgs); en un disco GPT sin partición `bios_grub`, la parte BIOS casi con seguridad fallaba antes de llegar a la EFI. Venía de `4fa0101`, que reemplazó el `systemd-boot` original (`daac08f`) por GRUB en modo BIOS; `684b971` le agregó `efiSupport` y `f35753d` lo pasó a Limine. | 2026-11-25, `8c5b808`: GRUB solo UEFI con `device = "nodev"`. |
| P11 | `install-msdos-pc.sh` usaba Limine sin ninguna partición FAT (desde `f35753d`). Limine solo lee particiones FAT (el instalador de NixOS lo dice: *"Limine cannot be installed on a system without an unencrypted partition formatted as FAT"*). Ese chequeo de `limine-install.py` (nixpkgs) solo corre con `efiSupport = false`: con `efiSupport = true` copiaba todo a `/boot/limine`, dentro de la ext4, sin quejarse, así que la instalación terminaba bien pero la PC probablemente no arrancaba. | 2026-11-25, `8c5b808`: GRUB solo BIOS en `/dev/${diskName}`. Ojo al copiar bloques de los scripts de VPS a los de PC: el disco tiene que ser `/dev/${diskName}`, nunca `/dev/vda`. |
| R3 | En discos con datos previos, `parted`/`mkfs` podían pedir confirmación leyendo de stdin, que es el propio script (`AGENTS.md` §6.2). | 2026-11-25: los 4 usan `parted -s` y `mkfs.ext4 -F` (`dad977e`, `f35753d`, `479bf18`). Cualquier comando nuevo que pueda preguntar algo tiene que usar su opción no interactiva o leer de `/dev/tty`. |

---

## 7. Cómo mantener este archivo

- **Cuándo:** en el mismo cambio (y el mismo commit) que lo afecta, junto con la entrada de `CHANGELOG.md`: cuando se prueba algo, cuando aparece o se corrige un problema, cuando cambia una diferencia de paridad o cuando se decide algo pendiente.
- **Encabezado:** actualizá la línea *"Actualizado al … contra el commit …"*. Si el cambio no está commiteado, decilo ahí y en las filas que correspondan (*"sin commitear"*); después de commitear, reemplazalo por el hash.
- **IDs:** `P` para problemas confirmados leyendo el código, `R` para riesgos que hay que verificar. Nunca se renumeran ni se reutilizan: el próximo problema nuevo es **P13** y el próximo riesgo, **R8**. `CHANGELOG.md` y `AGENTS.md` los citan.
- **Al corregir uno:** movelo de §4 o §5 a §6 (Corregidos), arriba de todo, con la fecha y el commit, y anotalo en `CHANGELOG.md`. Actualizá §1 si cambia el estado de algún script.
- **Al probar algo:** anotá en §1 qué se probó, dónde (VM con BIOS o UEFI, hardware real, Upcloud), con qué commit y en qué fecha, y sacalo de *"Qué probar primero"* (§2).
- **No arregles problemas sin que el usuario lo pida.** Este archivo los registra; corregirlos es otra tarea.
- `AGENTS.md` describe el proyecto y cambia poco. Si una novedad es de estado (qué funciona, qué está roto, qué falta), va acá, no en `AGENTS.md`.
