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

# Detailed instructions
1) Get MRPI for Kindlehf from [here](https://fw.notmarek.com/khf/), copy it to `Kindle USB root`.

2) Download both `.bin` pacakges from [usbnetlite Releases page](https://github.com/notmarek/kindle-usbnetlite/releases/tag/1.0.M](https://github.com/notmarek/kindle-usbnetlite)). Put the `.bin` file in `Kindle USB root/mrpackages`. Safely eject and unplug Kindle. Search for `;log mrpi` in the Kindle search bar. You should see an installation progress.

3) Prepare authorization keys. Download PuTTy for your machine and run `puttygen`. Generate a key (it will ask you to randomly move the mouse). Save the `.ppk` key in a secure place on PC, and test encryption key itself in a new file without extension named `authorized_keys`. Copy this file to `Kindle USB root/usbnetlite/etc/dropbear`. **Safely eject** and unplug Kindle.

4) **For Windows machines only**: download and install RNDIS driver from Microsoft. This is a common generic driver, you should be able to find it.

5) **While Kindle is unplugged** search for `;un` in the Kindle search bar.

6) Connect to PC - you should NOT see Kindle USB drive anymore.

7) Open Ethernet adapter settings and set this new connected device to IP=`192.168.15.100`, subnet mask=`255.255.255.0`, everything else by default.

8) Open your SSH/SFTPsoftware of choice. For example, WinSCP. Create a new connection, name it `Kindle USB` or something like that, target IP=`192.168.155.255` (this is usbnetlite's default), port `22` (default). In the connection settings -> SSH -> Authentication -> point it to the `.ppk` file you created.

9) Connect. It should warn you about a new key, accept it. See if you can access Kindle's storage and command line (PuTTy).

10) Autostart (! Do this **ONLY** if usbnetlite works!) Create and empty file without extension named `auto` in `Kindle USB root/usbnetlite/`. This will enable the usbnetlite after launching.

11) For a good measure, restart Kindle.

12) If you need to disable SSH, **plug in Kindle** (yes, connect) to PC and search for `;un` in the Kindle search bar again. If you forget, Kindle will kernel panic and restart, not a big deal. But if Autostart is enabled, it will enabled again.

This is it, now you should be able to access your Kindle's file system.
**A HUGE WARNING!!!** Now you have FULL access to Kindle's file system, be **very** careful about what you are doing!

Additional settings are in the `Kindle USB root/usbnetlite/etc/config` file. Add those lines, if they are not there:
`KINDLE_IP=192.168.15.255`: if you want to change it, in case you have multiple usbnetlite-enabled Kindles. Make sure to edit connection on PC if you do this.
`USE_WIFI="true"`: to enable SSH access over Wi-Fi. Kindle and PC must be on the same network. To get Kindle's IP address search for `;711` in the Kindle search bar and scroll down. Alternatively, tap `Network info` in KOReader's top menu, Network menu.
