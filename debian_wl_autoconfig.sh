#!/bin/sh

WL_CONF="/etc/systemd/network/30-wlan.network"

confirm_prompt() {
	read -p "Continue? [Y/n]: " choice

	case "$choice" in
		[Yy]*)
			return 1
			;;
		*)
			return 0
			;;
	esac
}

# Checks if non-free packages are enabled
check_sources() {
	echo "Before continuing, ensure the \"non-free\" component is enabled in apt sources (/etc/apt/sources.list)"
	
	confirm_prompt
	
	echo "Confirming..."
	if ! grep -E "^[^#].*non-free" "/etc/apt/sources.list" >/dev/null 2>&1; then
		echo "\"non-free\" component not found in apt sources (/etc/apt/sources.list)"
		exit 1
	fi
}

check_internet_connection() {
	echo "Checking for internet connection..."

	if ! ping -c 1 1.1.1.1 >/dev/null 2>&1; then
		echo "An internet connection is required to continue"
		exit 1
	fi
}

install_wl_drivers() {
	echo "Updating list of available packages..."
	sudo apt -y update >/dev/null 2>&1

	echo "Installing required package: linux-image-$(uname -r|sed 's,[^-]*-[^-]*-,,')..."
	sudo apt -y install linux-image-$(uname -r|sed 's,[^-]*-[^-]*-,,') >/dev/null 2>&1

	echo "Installing required package: linux-headers-$(uname -r|sed 's,[^-]*-[^-]*-,,')..."
	sudo apt -y install linux-headers-$(uname -r|sed 's,[^-]*-[^-]*-,,') >/dev/null 2>&1

	echo "Installing Broadcom wl drivers: broadcom-sta-dkms..."
	sudo apt -y install broadcom-sta-dkms >/dev/null 2>&1
}

configure_modules() {
	echo "Unloading conflicting modules (b44 b43 b43legacy ssb brcmsmac bcma)..."
	sudo modprobe -r b44 b43 b43legacy ssb brcmsmac bcma

	echo "Loading the wl module..."
	sudo modprobe wl
}

install_wpa_supplicant() {
	echo "Installing required package: wpasupplicant..."
	sudo apt -y install wpasupplicant >/dev/null 2>&1
}

purge_ifupdown() {
	echo "Purge package: ifupdown? (Purging the package \"ifupdown\" is recommended to reduce unintended side-effects)"

	if confirm_prompt; then
		echo "Purging Package: ifupdown..."
		sudo mv /etc/network/interfaces /etc/network/interfaces.save >/dev/null 2>&1
		sudo mv /etc/network/interfaces.d /etc/network/interfaces.d.save >/dev/null 2>&1
		sudo apt -y purge ifupdown >/dev/null 2>&1
	fi
}

# Reads input for network interface choice
choose_network_interface() {
	echo "Available network interfaces:"
	ip -o link show | awk -F': ' '{print $2}' | grep -v lo
	read -p "Enter the network interface for your wireless device (e.g., wlan0): " INTERFACE

	# Validate the interface
	if ! ip link show "$INTERFACE" >/dev/null 2>&1; then
		echo "Invalid network interface: $INTERFACE" >&2
		exit 1
	fi

	WPA_CONF="/etc/wpa_supplicant/wpa_supplicant-$INTERFACE.conf"
}

# Creates wireless interface configuration file
create_wl_conf() {
	echo "Creating wireless interface configuration file ($WL_CONF)"

	sudo touch $WL_CONF

	echo "[Match]
name=$INTERFACE
Type=wlan
WLANInterfaceType=station

[Network]
DHCP=ipv4

[DHCP]
UseDNS=yes" | sudo tee $WL_CONF >/dev/null 2>&1
}

# Creates wpa_supplicant configuration file
create_wpa_conf() {
	read -p "Enter SSID: " SSID
	read -p "Enter PSK: " PSK
	
	echo "Creating wpa_supplicant configuration file ($WPA_CONF)"

	sudo touch $WPA_CONF
	
	echo "ctrl_interface=DIR=/run/wpa_supplicant GROUP=netdev
update_config=1\n" | sudo tee $WPA_CONF >/dev/null 2>&1
	wpa_passphrase $SSID $PSK | sudo tee -a $WPA_CONF >/dev/null 2>&1
}

enable_services() {
	echo "Enabling service: wpa_supplicant@$INTERFACE.service"
	sudo systemctl enable --now wpa_supplicant@$INTERFACE.service >/dev/null 2>&1

	echo "Enabling service: systemd-networkd"
	sudo systemctl enable --now systemd-networkd >/dev/null 2>&1
}

optain_ip() {
	echo "Using DHCP to obtain an IP..."
	sudo dhclient $INTERFACE >/dev/null 2>&1
}

################################# MAIN #################################

check_sources
check_internet_connection
install_wl_drivers
configure_modules
install_wpa_supplicant
purge_ifupdown
choose_network_interface
create_wl_conf
create_wpa_conf
enable_services
optain_ip

echo "Complete."