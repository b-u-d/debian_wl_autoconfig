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

check_pkgs() {
	if dpkg-query -W -f='${Status}' linux-image-$(uname -r | sed 's,[^-]*-[^-]*-,,') | grep -q "ok installed" >/dev/null 2>&1 &&
		dpkg-query -W -f='${Status}' linux-headers-$(uname -r | sed 's,[^-]*-[^-]*-,,') | grep -q "ok installed" >/dev/null 2>&1 &&
		dpkg-query -W -f='${Status}' broadcom-sta-dkms | grep -q "ok installed" >/dev/null 2>&1; then
		return 0
	fi
	return 1
}

# Checks if non-free packages are enabled
check_sources() {
	if ! grep -q -E '(^[[:space:]]*deb[[:space:]]+[^#]*[[:space:]]+non-free[[:space:]]*$|^[[:space:]]*deb[[:space:]]+[^#]*[[:space:]]+non-free[[:space:]]+.*)' /etc/apt/sources.list /etc/apt/sources.list.d/* >/dev/null 2>&1; then
        echo "Non-free repository is not enabled in /etc/apt/sources.list"
        exit 1
    fi
	return 0
}

check_internet_connection() {
	if ! ping -c 1 1.1.1.1 >/dev/null 2>&1; then
		return 1
	fi
	return 0
}

install_broadcom_wl() {
    if ! check_pkgs && check_internet_connection; then
        echo "Updating list of available packages..."
        sudo apt -y update >/dev/null 2>&1

        if ! dpkg-query -W -f'${Status}' linux-image-$(uname -r | sed 's,[^-]*-[^-]*-,,') >/dev/null 2>&1 | grep -c "ok installed" >/dev/null 2>&1; then
            echo "Installing required package: linux-image-$(uname -r | sed 's,[^-]*-[^-]*-,,')..."
            sudo apt -y install linux-image-$(uname -r | sed 's,[^-]*-[^-]*-,,') >/dev/null 2>&1
        fi

        if ! dpkg-query -W -f'${Status}' linux-headers-$(uname -r | sed 's,[^-]*-[^-]*-,,') >/dev/null 2>&1 | grep -c "ok installed" >/dev/null 2>&1; then
            echo "Installing required package: linux-headers-$(uname -r | sed 's,[^-]*-[^-]*-,,')..."
            sudo apt -y install linux-headers-$(uname -r | sed 's,[^-]*-[^-]*-,,') >/dev/null 2>&1
        fi

		if check_sources; then
	        if ! dpkg-query -W -f'${Status}' broadcom-sta-dkms >/dev/null 2>&1 | grep -c "ok installed" >/dev/null 2>&1; then
    	        echo "Installing Broadcom wl drivers: broadcom-sta-dkms..."
        	    sudo apt -y install broadcom-sta-dkms >/dev/null 2>&1
        	fi
		fi
    elif check_pkgs && check_internet_connection; then
        echo "Updating list of available packages..."
        sudo apt -y update >/dev/null 2>&1
    elif ! check_pkgs && ! check_internet_connection; then
        echo "An internet connection is required to continue."
        exit 1
    else
        echo "The required packages are installed, but the list of available packages cannot be updated without a valid internet connection."
        if ! confirm_prompt; then
            exit 1
        fi
    fi
}

configure_modules() {
	echo "Unloading conflicting modules (b44 b43 b43legacy ssb brcmsmac bcma)..."
	sudo modprobe -r b44 b43 b43legacy ssb brcmsmac bcma

	echo "Loading the wl module..."
	sudo modprobe wl
}

install_wpa_supplicant() {
	if ! dpkg-query -W -f'${Status}' wpasupplicant >/dev/null 2>&1 | grep -c "ok installed" >/dev/null 2>&1; then
		echo "Installing required package: wpasupplicant..."
		sudo apt -y install wpasupplicant >/dev/null 2>&1
	fi
}

purge_ifupdown() {
	if dpkg-query -W -f'${Status}' ifupdown >/dev/null 2>&1 | grep -c "ok installed" >/dev/null 2>&1; then
		echo "Purge package: ifupdown? (Purging ifupdown is recommended to reduce unintended side-effects)"

		if confirm_prompt; then
			sudo mv /etc/network/interfaces /etc/network/interfaces.save >/dev/null 2>&1
			sudo mv /etc/network/interfaces.d /etc/network/interfaces.d.save >/dev/null 2>&1
			echo "Purging Package: ifupdown..."
			sudo apt -y remove --purge ifupdown >/dev/null 2>&1
		fi
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

install_broadcom_wl
configure_modules
install_wpa_supplicant
purge_ifupdown
choose_network_interface
create_wl_conf
create_wpa_conf
enable_services
optain_ip

echo "Complete."
