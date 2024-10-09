# debian wl autoconfiguration script

Shell script that automatically installs and configures [wl drivers](https://packages.debian.org/search?keywords=broadcom-sta-dkms) and [wpa_supplicant](https://packages.debian.org/search?keywords=wpasupplicant) as a systemd service on Debian Standard.
Tested and working on Debian 12 Standard with the Broadcom BCM4352 chip.

## Requirements
- Debian Standard
- An internet connection
- Knowing the name of your wireless network device (`ip link show`)

## Usage
Clone this Repository:
```bash
git clone https://github.com/b-u-d/debian_wl_autoconfig.git
cd debian_wl_autoconfig
```

Make the Script Executable:
```bash
chmod +x debian_wl_autoconfig.sh
```

Run the Script:
```bash
./autoconfigure.sh
```
