# nixos-first-install
Primera instalación de NixOS para servers VPS. Probado en servers Upcloud.

## Comandos:

<h3 style="text-align: center"> Para servidores VPS </h3>

Al recién crear el VPS Nixos va a bootear el CD/DVD de instalacion. Entonces correr uno de estos comandos que estan a continuación.


#### Para discos MBR (BIOS):
Especialmente creado para máquinas virtuales.

*(¡Este es el correcto para VPS Upcloud!)*
```bash
curl -sSL https://raw.githubusercontent.com/mjb10/nixos-first-install/refs/heads/main/install-mbr.sh | bash
```

#### Comando CURL para discos GPT (UEFI): 
Especialmente creado para máquinas virtuales.

*(No copiar este comando para Upcloud)*
```bash
curl -sSL https://raw.githubusercontent.com/mjb10/nixos-first-install/refs/heads/main/install-gpt.sh | bash
```

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

<h3 style="text-align: center"> Para PCs </h3>

#### Para discos MBR (BIOS):
```bash
curl -sSL https://raw.githubusercontent.com/mjb10/nixos-first-install/refs/heads/main/install-mbr-for-pc.sh | bash
```

#### Comando CURL para discos GPT (UEFI): 
```bash
curl -sSL https://raw.githubusercontent.com/mjb10/nixos-first-install/refs/heads/main/install-gpt-for-pc.sh | bash
```