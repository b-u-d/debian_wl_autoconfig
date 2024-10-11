#!/bin/sh

WL_CONF="/etc/systemd/network/30-wlan.network"
KERNEL_VERSION=$(uname -r | sed 's,[^-]*-[^-]*-,,')

confirm_prompt() {
	read -p "Continue? [Y/n]: " choice
	case "$choice" in
	[Yy]* | "") return 0 ;; # Yes
	*) return 1 ;;          # No
	esac
}

# Check for an internet connection
check_internet() {
	local ips=("1.1.1.1" "8.8.8.8")
	for ip in "${ips[@]}"; do
		if ping -c 5 -W 5 "$ip" >/dev/null 2>&1; then
			return 0 # Success
		fi
	done
	return 1 # Failure
}

# Check if all the required packages are installed
check_pkgs() {
	local packages=(
		"linux-image-$KERNEL_VERSION"
		"linux-headers-$KERNEL_VERSION"
		"broadcom-sta-dkms"
	)

	for pkg in "${packages[@]}"; do
		if ! dpkg-query -W -f='${Status}' "$pkg" | grep -q "install ok installed"; then
			return 1 # Package not installed
		fi
	done
	return 0 # All packages installed
}

# Check if the broadcom-package is available
check_apt_wl() {
	if ! apt-cache show broadcom-sta-dkms >/dev/null 2>&1; then
		echo "Unable to install package: broadcom-sta-dkms"
		echo "Ensure you have the non-free repository enabled in /etc/apt/sources.list"
		exit 1 # Unable to continue without access to the driver installation files
	fi
}

# Install the broadcom wl drivers and required packages
install_broadcom_wl() {
	if check_internet; then
		echo "Updating list of available packages..."
		sudo apt -y update >/dev/null 2>&1

		if ! check_pkgs; then
			local packages=(
				"linux-image-$KERNEL_VERSION"
				"linux-headers-$KERNEL_VERSION"
			)

			for pkg in "${packages[@]}"; do
				if ! dpkg-query -W -f='${Status}' "$pkg" | grep -q "install ok installed"; then
					echo "Installing required package: $pkg..."
					sudo apt -y install "$pkg" >/dev/null 2>&1
				fi
			done

			# Check for the broadcom package availability
			check_apt_wl

			if ! dpkg-query -W -f='${Status}' broadcom-sta-dkms | grep -q "install ok installed"; then
				echo "Installing Broadcom wl drivers: broadcom-sta-dkms..."
				sudo apt -y install broadcom-sta-dkms >/dev/null 2>&1
			fi
		fi
	else
		if check_pkgs; then
			echo "Required packages are installed, but cannot update package list without internet."
			if ! confirm_prompt; then
				exit 1
			fi
		else
			echo "ERROR: Unable to install Broadcom wl drivers."
			echo "Ensure you have a working internet connection and the non-free repository enabled."
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
	if ! dpkg-query -W -f='${Status}' wpasupplicant | grep -q "install ok installed"; then
		echo "Installing required package: wpasupplicant..."
		sudo apt -y install wpasupplicant >/dev/null 2>&1
	fi
}

purge_ifupdown() {
	if dpkg-query -W -f='${Status}' ifupdown | grep -q "install ok installed"; then
		echo "Purge package: ifupdown? (Purging ifupdown is recommended to reduce unintended side-effects)"
		if confirm_prompt; then
			echo "Backing up interfaces configuration..."
			sudo mv /etc/network/interfaces{,.save} >/dev/null 2>&1
			sudo mv /etc/network/interfaces.d{,.save} >/dev/null 2>&1
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
	{
		echo "[Match]"
		echo "name=$INTERFACE"
		echo "Type=wlan"
		echo "WLANInterfaceType=station"
		echo ""
		echo "[Network]"
		echo "DHCP=ipv4"
		echo ""
		echo "[DHCP]"
		echo "UseDNS=yes"
	} | sudo tee "$WL_CONF" >/dev/null 2>&1
}

# Creates wpa_supplicant configuration file
create_wpa_conf() {
	read -p "Enter SSID: " SSID
	read -p "Enter PSK: " PSK

	echo "Creating wpa_supplicant configuration file ($WPA_CONF)"
	{
		echo "ctrl_interface=DIR=/run/wpa_supplicant GROUP=netdev"
		echo "update_config=1"
		wpa_passphrase "$SSID" "$PSK"
	} | sudo tee "$WPA_CONF" >/dev/null 2>&1
}

enable_services() {
	echo "Enabling service: wpa_supplicant@$INTERFACE.service"
	sudo systemctl enable --now wpa_supplicant@"$INTERFACE".service >/dev/null 2>&1
	echo "Enabling service: systemd-networkd"
	sudo systemctl enable --now systemd-networkd >/dev/null 2>&1
}

obtain_ip() {
	echo "Using DHCP to obtain an IP..."
	sudo dhclient "$INTERFACE" >/dev/null 2>&1
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
obtain_ip

echo "Complete."
