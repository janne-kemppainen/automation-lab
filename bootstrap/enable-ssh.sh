#!/usr/bin/env bash
# Day-0-alustus: ottaa SSH:n käyttöön FRR-reitittimissä.
# Vastaa kampuslabran Cisco-laitteille konsolista tehtävää SSH-peruskonfiguraatiota.
# Ajetaan WSL:ssä aina labran käynnistyksen jälkeen, koska reitittimiin tehdyt muutokset eivät säily.
set -euo pipefail

LAB="clab-hamk-verkonhallinta-golden"
ROUTERS="r1 r2 r3"
ADMIN_USER="netadmin"
PUBKEY="$(cat "${HOME}/.ssh/automation_lab.pub")"

for r in $ROUTERS; do
  echo "== ${r}"
  docker exec -i "${LAB}-${r}" sh -s "$ADMIN_USER" "$PUBKEY" <<'EOF'
set -e
USER_NAME="$1"
KEY="$2"
apk add --no-cache openssh sudo >/dev/null
ssh-keygen -A >/dev/null
if ! id "$USER_NAME" >/dev/null 2>&1; then
  adduser -D -s /bin/sh "$USER_NAME"
fi
# Satunnainen salasana: tili ei ole lukittu, mutta kirjautuminen sallitaan vain avaimella
echo "$USER_NAME:$(head -c 24 /dev/urandom | base64)" | chpasswd
mkdir -p "/home/$USER_NAME/.ssh"
echo "$KEY" > "/home/$USER_NAME/.ssh/authorized_keys"
chown -R "$USER_NAME:$USER_NAME" "/home/$USER_NAME/.ssh"
chmod 700 "/home/$USER_NAME/.ssh"
chmod 600 "/home/$USER_NAME/.ssh/authorized_keys"
echo "$USER_NAME ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/$USER_NAME"
chmod 440 "/etc/sudoers.d/$USER_NAME"
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
touch /etc/frr/vtysh.conf
pgrep -x sshd >/dev/null || /usr/sbin/sshd
echo "SSH valmis: $(hostname)"
EOF
done