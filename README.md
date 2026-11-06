# nixos-first-install
Scripts para primera instalación de NixOS para servers VPS probados en Upcloud y para computadoras personales.

---
<div align="center">
    <h3> Comandos para servidores VPS </h3>
</div>

Al recién crear el VPS Nixos va a bootear el CD/DVD de instalacion. Entonces correr uno de estos comandos que estan a continuación.


#### Para discos MBR (BIOS):

*(¡Este es el correcto para VPS Upcloud!)*
```bash
curl -sSL https://raw.githubusercontent.com/mjb10/nixos-first-install/refs/heads/main/install-mbr.sh | bash
```
---

#### Comando CURL para discos GPT (UEFI): 

```bash
curl -sSL https://raw.githubusercontent.com/mjb10/nixos-first-install/refs/heads/main/install-gpt.sh | bash
```
---
#### Próximos pasos:

Durante la ejecución del script se consultará el nombre para el nuevo usuario y su clave. Luego de apagado el server y quitado CD/DVD de instalación: encender el server.

Luego loguearse con el nuevo usuario via ssh:
```bash
ssh -o UserKnownHostsFile=/tmp/known_hosts_tmp -o StrictHostKeyChecking=no [nombre de usuario creado]@[IP del servidor]
```

Una vez ingresado al server con usuario 'nixi' ejecutar este comando:
```bash
connect-repo
```
Seguir los pasos. EL VPS se va actualizar con el nuevo repo y se reiniciará.

<br>

<div align="center">
    <h3> Comandos para PCs </h3>
</div>

#### Para discos MBR (BIOS):
```bash
curl -sSL https://raw.githubusercontent.com/mjb10/nixos-first-install/refs/heads/main/install-mbr-for-pc.sh | bash
```
---
#### Para discos GPT (UEFI): 
```bash
curl -sSL https://raw.githubusercontent.com/mjb10/nixos-first-install/refs/heads/main/install-gpt-for-pc.sh | bash
```