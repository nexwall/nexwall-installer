#!/bin/bash
# NEXWALL interactive disk installer. Runs on tty1 of the live system.
set -Eeuo pipefail

APP_DIR=/opt/nexwall-installer
IMAGE="$APP_DIR/payload.img.gz"
HASH_FILE="$APP_DIR/SHA256SUM"      # SHA-256 of the DECOMPRESSED image
SIZE_FILE="$APP_DIR/SIZE"           # size in bytes of the decompressed image
VERSION_FILE="$APP_DIR/VERSION"
LOG=/var/log/nexwall-installer.log
TTY=/dev/tty1

: > "$LOG"
log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG"; }

export LANG=C.UTF-8 LC_ALL=C.UTF-8
LANGSEL=en

# ------------------------------------------------------------------------------------------ messages (en, es, pt)
declare -A M
msg() { local k="$1"; shift; local t="${M[${LANGSEL}.$k]:-${M[en.$k]}}"; printf "$t" "$@"; }
M[en.intro]='This utility installs NEXWALL %s on an internal disk.\n\nALL DATA on the disk you select will be erased.\n\nContinue to disk selection?'
M[es.intro]='Esta utilidad instala NEXWALL %s en un disco interno.\n\nSe BORRARÁN TODOS LOS DATOS del disco que seleccione.\n\n¿Continuar con la selección del disco?'
M[pt.intro]='Este utilitário instala o NEXWALL %s em um disco interno.\n\nTODOS OS DADOS do disco selecionado serão APAGADOS.\n\nContinuar para a seleção do disco?'
M[en.checking]='Checking the installation image...'
M[es.checking]='Comprobando la imagen de instalación...'
M[pt.checking]='Verificando a imagem de instalação...'
M[en.err_payload]='Installer payload is incomplete (%s is missing or empty).'
M[es.err_payload]='El contenido del instalador está incompleto (%s falta o está vacío).'
M[pt.err_payload]='O conteúdo do instalador está incompleto (%s não existe ou está vazio).'
M[en.err_hash]='The embedded SHA-256 value is invalid.'
M[es.err_hash]='El valor SHA-256 incluido no es válido.'
M[pt.err_hash]='O valor SHA-256 incluído não é válido.'
M[en.err_size]='The embedded image size is invalid.'
M[es.err_size]='El tamaño de la imagen incluida no es válido.'
M[pt.err_size]='O tamanho da imagem incluída não é válido.'
M[en.err_gzip]='The embedded image is damaged (gzip test failed). Do not install.'
M[es.err_gzip]='La imagen incluida está dañada (falló la prueba gzip). No instale.'
M[pt.err_gzip]='A imagem incluída está danificada (o teste gzip falhou). Não instale.'
M[en.err_verify]='The embedded image failed SHA-256 verification. Do not install.'
M[es.err_verify]='La imagen incluida no pasó la verificación SHA-256. No instale.'
M[pt.err_verify]='A imagem incluída falhou na verificação SHA-256. Não instale.'
M[en.warn_live]='Warning: the installation USB could not be identified, so it is NOT excluded from the list. Check the disk names carefully.\n\nContinue?'
M[es.warn_live]='Aviso: no se pudo identificar la memoria USB de instalación, por lo que NO se excluye de la lista. Revise con cuidado los nombres de los discos.\n\n¿Continuar?'
M[pt.warn_live]='Aviso: não foi possível identificar o pendrive de instalação, então ele NÃO é excluído da lista. Confira com cuidado os nomes dos discos.\n\nContinuar?'
M[en.err_nodisk]='No eligible internal disk was found. The disk must be detected, non-removable and at least %s bytes. The installation USB is excluded.'
M[es.err_nodisk]='No se encontró ningún disco interno válido. El disco debe estar detectado, no ser extraíble y tener al menos %s bytes. La memoria USB de instalación se excluye.'
M[pt.err_nodisk]='Nenhum disco interno elegível foi encontrado. O disco deve ser detectado, não removível e ter pelo menos %s bytes. O pendrive de instalação é excluído.'
M[en.menu]='Choose the disk to ERASE and install NEXWALL %s on.\n\nThe installation USB is not listed.'
M[es.menu]='Elija el disco que se BORRARÁ para instalar NEXWALL %s.\n\nLa memoria USB de instalación no aparece en la lista.'
M[pt.menu]='Escolha o disco que será APAGADO para instalar o NEXWALL %s.\n\nO pendrive de instalação não aparece na lista.'
M[en.err_gone]='The selected disk is no longer available.'
M[es.err_gone]='El disco seleccionado ya no está disponible.'
M[pt.err_gone]='O disco selecionado não está mais disponível.'
M[en.err_usb]='Safety check blocked the installation USB as a target.'
M[es.err_usb]='La comprobación de seguridad bloqueó la memoria USB de instalación como destino.'
M[pt.err_usb]='A verificação de segurança bloqueou o pendrive de instalação como destino.'
M[en.confirm]='You are about to ERASE ALL DATA on:\n\n%s\n\nNEXWALL %s, %s bytes.\n\nType INSTALL (capital letters) to proceed.'
M[es.confirm]='Va a BORRAR TODOS LOS DATOS de:\n\n%s\n\nNEXWALL %s, %s bytes.\n\nEscriba INSTALL (en mayúsculas) para continuar.'
M[pt.confirm]='Você vai APAGAR TODOS OS DADOS de:\n\n%s\n\nNEXWALL %s, %s bytes.\n\nDigite INSTALL (em maiúsculas) para continuar.'
M[en.writing]='Writing NEXWALL %s to %s.\n\nDo not power off or remove the USB.\nThis takes a few minutes.'
M[es.writing]='Escribiendo NEXWALL %s en %s.\n\nNo apague el equipo ni quite la memoria USB.\nEsto tarda unos minutos.'
M[pt.writing]='Gravando o NEXWALL %s em %s.\n\nNão desligue o equipamento nem retire o pendrive.\nIsso leva alguns minutos.'
M[en.err_write]='Writing the image failed (gzip %s, dd %s). Review %s.'
M[es.err_write]='Falló la escritura de la imagen (gzip %s, dd %s). Revise %s.'
M[pt.err_write]='Falha ao gravar a imagem (gzip %s, dd %s). Veja %s.'
M[en.verifying]='Verifying what was written to %s...'
M[es.verifying]='Verificando lo escrito en %s...'
M[pt.verifying]='Verificando o que foi gravado em %s...'
M[en.err_readback]='Read-back verification failed. Do not deploy this disk.'
M[es.err_readback]='Falló la verificación de lectura. No use este disco.'
M[pt.err_readback]='A verificação de leitura falhou. Não use este disco.'
M[en.done]='NEXWALL %s was written and verified.\n\nRemove the USB installation media, then choose Yes to restart. The first start of the new system opens the setup wizard.'
M[es.done]='NEXWALL %s se escribió y verificó.\n\nQuite la memoria USB de instalación y elija Sí para reiniciar. El primer arranque del nuevo sistema abre el asistente de configuración.'
M[pt.done]='O NEXWALL %s foi gravado e verificado.\n\nRetire o pendrive de instalação e escolha Sim para reiniciar. A primeira inicialização do novo sistema abre o assistente de configuração.'
M[en.done_no]='Installation verified. You can power off, remove the USB and boot from the internal disk.'
M[es.done_no]='Instalación verificada. Puede apagar, quitar la memoria USB y arrancar desde el disco interno.'
M[pt.done_no]='Instalação verificada. Você pode desligar, retirar o pendrive e iniciar pelo disco interno.'
M[en.yes]='Yes'
M[es.yes]='Sí'
M[pt.yes]='Sim'
M[en.no]='No'
M[es.no]='No'
M[pt.no]='Não'
M[en.log]='Log: %s'
M[es.log]='Registro: %s'
M[pt.log]='Log: %s'

# The dialogs talk to the console directly, so the log redirection never touches the screen.
W() {
  local extra=()
  [[ "$1" == --yesno ]] && extra=(--yes-button "$(msg yes)" --no-button "$(msg no)")
  whiptail --title "NEXWALL Installer" "${extra[@]}" "$@" 3>&1 1>"$TTY" 2>&3 <"$TTY"
}
say() { W --msgbox "$1" 14 78 || true; }
fail() { log "ERROR: $1"; say "$1\n\n$(msg log "$LOG")"; exit 1; }

[[ $EUID -eq 0 ]] || { echo "Run as root"; exit 1; }

# First screen: the language of the installer.
LANGSEL=$(W --menu "Language / Idioma / Idioma" 14 60 3 en "English" es "Español" pt "Português") || exit 0
for f in "$IMAGE" "$HASH_FILE" "$SIZE_FILE" "$VERSION_FILE"; do
  [[ -s "$f" ]] || fail "$(msg err_payload "$f")"
done
VERSION=$(tr -d '\r\n' < "$VERSION_FILE")
EXPECTED=$(awk 'NR==1 {print tolower($1)}' "$HASH_FILE")
IMG_BYTES=$(tr -d '\r\n' < "$SIZE_FILE")
[[ "$EXPECTED" =~ ^[a-f0-9]{64}$ ]] || fail "$(msg err_hash)"
[[ "$IMG_BYTES" =~ ^[0-9]+$ ]] || fail "$(msg err_size)"
log "NEXWALL $VERSION, image $IMG_BYTES bytes, sha256 $EXPECTED"

W --yesno "$(msg intro "$VERSION")" 14 78 || exit 0

# 1. Verify the payload before touching any disk.
W --infobox "$(msg checking)" 7 60
gzip -t "$IMAGE" || fail "$(msg err_gzip)"
ACTUAL=$(gzip -dc "$IMAGE" | sha256sum | awk '{print $1}')
[[ "$ACTUAL" == "$EXPECTED" ]] || fail "$(msg err_verify)"
log "payload verified"

# 2. Find the disk the live medium runs from, so it is never offered.
LIVE_DISK=""
for MP in /run/live/medium /run/live /lib/live/mount/medium; do
  SRC=$(findmnt -rn -o SOURCE "$MP" 2>/dev/null | head -n1 || true)
  [[ "$SRC" == /dev/* ]] || continue
  SRC=$(readlink -f "$SRC")
  PARENT=$(lsblk -ndo PKNAME "$SRC" 2>/dev/null | head -n1 || true)
  LIVE_DISK=${PARENT:+/dev/$PARENT}
  LIVE_DISK=${LIVE_DISK:-$SRC}
  break
done
log "live disk: ${LIVE_DISK:-unknown}"

# 3. Eligible targets: whole, non-removable disks that are large enough.
MENU=()
while read -r NAME TYPE RM SIZE TRAN MODEL; do
  [[ "$TYPE" == disk && "$RM" == 0 && -b "$NAME" ]] || continue
  [[ -z "$LIVE_DISK" || "$(readlink -f "$NAME")" != "$LIVE_DISK" ]] || continue
  BYTES=$(blockdev --getsize64 "$NAME" 2>/dev/null || echo 0)
  (( BYTES >= IMG_BYTES )) || continue
  MENU+=("$NAME" "$SIZE ${TRAN:--} ${MODEL:-disk}")
done < <(lsblk -dnpo NAME,TYPE,RM,SIZE,TRAN,MODEL)

if [[ -z "$LIVE_DISK" ]]; then
  W --yesno "$(msg warn_live)" 12 78 || exit 0
fi
((${#MENU[@]} >= 2)) || fail "$(msg err_nodisk "$IMG_BYTES")"

TARGET=$(W --menu "$(msg menu "$VERSION")" 20 90 8 "${MENU[@]}") || exit 0
[[ -b "$TARGET" ]] || fail "$(msg err_gone)"
[[ -z "$LIVE_DISK" || "$(readlink -f "$TARGET")" != "$LIVE_DISK" ]] || fail "$(msg err_usb)"

ANSWER=$(W --inputbox "$(msg confirm "$TARGET" "$VERSION" "$IMG_BYTES")" 18 78 "") || exit 0
[[ "$ANSWER" == "INSTALL" ]] || exit 0

# 4. Write.
log "writing to $TARGET"
W --infobox "$(msg writing "$VERSION" "$TARGET")" 10 70
while read -r PART; do
  [[ -n "$PART" ]] && umount "$PART" 2>/dev/null || true
done < <(lsblk -lnpo NAME "$TARGET" | tail -n +2)
swapoff -a 2>/dev/null || true

set +e
gzip -dc "$IMAGE" | dd of="$TARGET" bs=16M iflag=fullblock oflag=direct conv=fsync status=none 2>>"$LOG"
RC=("${PIPESTATUS[@]}")
set -e
(( RC[0] == 0 && RC[1] == 0 )) || fail "$(msg err_write "${RC[0]}" "${RC[1]}" "$LOG")"
sync
blockdev --flushbufs "$TARGET" 2>/dev/null || true
udevadm settle 2>/dev/null || true

# 5. Read back from the disk itself (direct I/O, no page cache) and compare.
W --infobox "$(msg verifying "$TARGET")" 7 70
READBACK=$(dd if="$TARGET" bs=16M iflag=direct,count_bytes count="$IMG_BYTES" status=none 2>>"$LOG" | sha256sum | awk '{print $1}')
log "read-back sha256 $READBACK"
[[ "$READBACK" == "$EXPECTED" ]] || fail "$(msg err_readback)"

if W --yesno "$(msg done "$VERSION")" 14 78; then
  sync; systemctl reboot
else
  say "$(msg done_no)"
fi
