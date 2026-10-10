simple usbnet for kindle -- only stuff you **NEED**
# Installation Instructions
1. Download the `update.bin` file from Released
2. Place it into the `mrpackages` folder on your kindle
3. Run `;log mrpi` from the search bar
4. Profit! You should be able to control usbnetlite from KUAL

# Connection Info
There is a config file you can edit with KOReader, here is the default connection info:  
```
username: root
password: kindle
```


# Wi-Fi-only SSH

USB networking remains the default. To run SSH without changing the USB gadget
mode, select **Enable Wi-Fi-only SSH (no USB switch)** in KUAL, then **Start
Wi-Fi SSH**. Stop the existing SSH/USB networking session before changing modes.
The same configuration can be set in `/mnt/us/usbnetlite/etc/config`:

```sh
USE_WIFI="true"
USE_WIFI_SSHD_ONLY="true"
```

Use **Enable SSH at boot** to create the existing `usbnetlite/auto` marker. In
Wi-Fi-only mode, a separate Upstart task runs after `framework` starts. Its helper
is installed on the system partition and waits up to 120 seconds for the userstore
and `wlan0`. Dropbear binds `wlan0` rather than a DHCP address, so the daemon can
start before Wi-Fi receives an IP address. The boot log is
`/var/local/usbnetlite/wifi-boot.log`.

**Start Wi-Fi SSH** is idempotent: starting an already running server does not
stop it. **Stop Wi-Fi SSH** stops the matching server and removes the Wi-Fi SSH
firewall rule. The existing toggle action also works in Wi-Fi-only mode without
calling the USB gadget-switching commands. Direct shell equivalents are:

```sh
/mnt/us/usbnetlite/bin/sshd-control start
/mnt/us/usbnetlite/bin/sshd-control status
/mnt/us/usbnetlite/bin/sshd-control stop
```

This helper invokes `dropbearmulti dropbear` directly, so a missing
`/usr/bin/dropbear` symlink does not prevent Wi-Fi SSH startup. If a firmware update
removed the system-partition boot jobs or helper, reinstall the package to restore
them. Existing custom configuration, host keys, and authorized keys are retained.
USB mass-storage mode can make the userstore unavailable: safely eject the Kindle
before using its extensions or connecting over Wi-Fi. If the userstore or Wi-Fi
interface remains unavailable beyond the boot wait, start SSH from KUAL once it
is available.

# Development checks

Run the isolated shell regression tests without a Kindle or cross-compilation
toolchain:

```sh
python3 -m unittest discover -s tests -v
```

Building an OTA package still requires the existing `khf` koxtoolchain and
KindleTool setup used by `package.sh`.
