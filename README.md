# nixos-first-install
Scripts para primera instalación de NixOS para servers VPS probados en Upcloud y para computadoras personales.

---
<div align="center">
    <h3> Comandos para servidores VPS </h3>
</div>

Al recién crear el VPS Nixos va a bootear el CD/DVD de instalacion. Entonces optar por uno de estos comandos que estan a continuación.

#### (Opción 1) Para discos MBR/MSDOS (BIOS):

*(¡Este es el correcto para VPS Upcloud!)*
```bash
curl -sSL https://raw.githubusercontent.com/mjb10/nixos-first-install/refs/heads/main/install-msdos.sh | bash
```
---

#### (Opción 2) Para discos GPT (UEFI): 

```bash
curl -sSL https://raw.githubusercontent.com/mjb10/nixos-first-install/refs/heads/main/install-gpt.sh | bash
```
---
#### Próximos pasos:

**1.** Durante la ejecución del script se consultará el nombre para el nuevo usuario, su clave y el nombre del perfil de Nix (si vas a usar `connect-repo`, tiene que coincidir con el nombre de la configuración en el `flake.nix` del repo, `nixosConfigurations.<nombre>`; si lo dejás vacío se usa `nixos`) y el dominio de Headscale (por ejemplo `headscale.midominio.com`). **Antes de encender el server**, ese dominio tiene que tener un registro DNS A apuntando a la IP pública del server, con los puertos 80 y 443 abiertos: se usan para sacar el certificado HTTPS (Let's Encrypt). Si no tenés dominio, dejalo vacío: el script muestra la IP que detectó y te deja confirmarla o escribir otra, y Headscale queda en `http://[IP]:8080`, sin HTTPS (no recomendado: los dispositivos no pueden verificar que hablan con tu server, y alguna app de Tailscale podría no aceptarlo). Luego de apagado el server y quitado CD/DVD de instalación: encender el server.

**2.** Luego loguearse con el nuevo usuario via ssh:
```bash
ssh -o UserKnownHostsFile=/tmp/known_hosts_tmp -o StrictHostKeyChecking=no [nombre de usuario creado]@[IP del servidor]
```

**3.** Una vez ingresado al server con usuario 'nixi' ejecutar este comando:
```bash
connect-repo
```
**4.** Seguir los pasos. Después de la URL del repo se pide el nombre de la rama: si lo dejás vacío, se usa la rama principal del repo. El VPS se va a actualizar con el nuevo repo y se reiniciará. Si la actualización falla (por ejemplo, porque la rama no existe), no se reinicia: revisá el error y volvé a intentar con `update && sudo reboot`.

**5. Tailnet (Headscale + Tailscale).** El server corre Headscale (el servidor de coordinación de Tailscale) en `https://[dominio de Headscale]` (o en `http://[IP]:8080` si no pusiste dominio; en ese caso, usá esa URL en lugar de la del dominio en todo lo que sigue) y, desde el primer arranque, se une solo a su propia tailnet como un nodo más. Para comprobarlo: `tailscale status`. Para sumar otro dispositivo, ejecutá en el server:
```bash
tailnet-key
```
Muestra una clave de un solo uso (vence en 1 hora) y el comando para ejecutar en el dispositivo nuevo (`sudo tailscale up --login-server https://[dominio de Headscale] --auth-key …`). En las apps de Tailscale (Android, iOS, macOS, Windows), configurá `https://[dominio de Headscale]` como servidor personalizado e iniciá sesión: la página que se abre muestra un comando `headscale auth register …` que se ejecuta en el server con `sudo`.

⚠️ La tailnet solo sigue funcionando después de `connect-repo` si el `flake.nix` del repo también configura Headscale (con la misma URL), Caddy (si usás dominio) y Tailscale.

<br>

<div align="center">
    <h3> Comandos para PCs </h3>
</div>

#### (Opción 1) Para discos MBR/MSDOS (BIOS):
```bash
curl -sSL https://raw.githubusercontent.com/mjb10/nixos-first-install/refs/heads/main/install-msdos-pc.sh | bash
```
---
#### (Opción 2) Para discos GPT (UEFI): 
```bash
curl -sSL https://raw.githubusercontent.com/mjb10/nixos-first-install/refs/heads/main/install-gpt-pc.sh | bash
```
---
#### Sumar la PC a la tailnet del VPS:

⚠️ Por ahora `connect-tailnet` solo viene en la opción 1 (MBR/MSDOS): en `install-gpt-pc.sh` está desactivado.

Las PCs no corren Headscale: se suman como clientes a la tailnet del VPS (paso 5 de VPS). Primero ejecutá `tailnet-key` en el VPS. Después, en la PC:
```bash
connect-tailnet
```
Te pide la URL de Headscale y la clave que mostró `tailnet-key` (la clave no se ve mientras la escribís). Si falla, generá otra clave con `tailnet-key`: cada una sirve una sola vez y vence en 1 hora.