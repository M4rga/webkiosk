#!/bin/bash

set -e

if [ "$EUID" != '0' ]; then
    echo 'This script must be run as root' >&2
    exit 1
fi

apt-get update
apt-get install -y --no-install-recommends xorg chromium
apt-get install -y xserver-xorg-legacy

if [ ! -e ~kioskuser ]; then
    useradd -Um kioskuser
fi

cat << 'EOF' > ~kioskuser/.xinitrc
#!/bin/bash

set -e

# Get display resolution

DISPLAY_RESOLUTION="$(xrandr --current | grep '*' | uniq | awk '{print $1}')"
DISPLAY_RES_W="$(echo $DISPLAY_RESOLUTION | cut -dx -f1 | sed 's/[^0-9]*//g')"
DISPLAY_RES_H="$(echo $DISPLAY_RESOLUTION | cut -dx -f2 | sed 's/[^0-9]*//g')"

# Disable Xorg screen blanking and DPMS

xset s off -dpms

# Disable some keys (see https://stackoverflow.com/a/44804851)

xmodmap -e 'keycode 37 = '   # Disable the CTRL_L key in the current display
xmodmap -e 'keycode 105 = '  # Disable the CTRL_R key in the current display

xmodmap -e 'keycode 64 = '   # Disable the Alt_L key in the current display
xmodmap -e 'keycode 204 = '

xmodmap -e 'keycode 133 = '  # Disable the Super_L key in the current display
xmodmap -e 'keycode 134 = '  # Disable the Super_R key in the current display

xmodmap -e 'keycode 67 = Escape'  # Disable the F1 key in the current display
xmodmap -e 'keycode 71 = Escape'  # Disable the F5 key in the current display

# Start Chromium in kiosk mode
# For more information on the command line options, see the following link:
# https://peter.sh/experiments/chromium-command-line-switches/

chromium --kiosk \
    --window-position=0,0 --window-size="$DISPLAY_RES_W,$DISPLAY_RES_H" \
    --disable-translate --disable-sync --noerrdialogs --no-message-box \
    --no-first-run --start-fullscreen --disable-hang-monitor \
    --disable-infobars --disable-logging --disable-sync \
    --disable-settings-window \
    'https://changethis.com'
EOF

chown kioskuser:kioskuser ~kioskuser/.xinitrc
chmod 644 ~kioskuser/.xinitrc

cat << 'EOF' > ~kioskuser/.profile
# If $DISPLAY is not defined and I'm on TTY7
if [ -z "$DISPLAY" ] && [ "$XDG_VTNR" = 7 ]; then
    # Run startx replacing the current process
    exec /usr/bin/startx
fi
EOF

chown kioskuser:kioskuser ~kioskuser/.profile
chmod 644 ~kioskuser/.profile

cat << 'EOF' > /etc/systemd/system/kiosk.service
[Unit]
Description=startx on tty7

# Disable unit start rate limiting
StartLimitIntervalSec=0

[Service]
Type=simple

WorkingDirectory=/home/kioskuser
ExecStartPre=/bin/chvt 7
ExecStart=/bin/su -l kioskuser

StandardInput=tty
StandardOutput=tty
StandardError=tty
TTYPath=/dev/tty7

Restart=always
RestartSec=5

[Install]
WantedBy=getty.target
EOF

chmod 644 /etc/systemd/system/kiosk.service

systemctl daemon-reload
systemctl enable kiosk
systemctl restart kiosk
