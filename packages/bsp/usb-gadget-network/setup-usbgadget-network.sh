#!/bin/bash

deviceinfo_name="USB Gadget Network"
deviceinfo_manufacturer="Armbian"
#deviceinfo_usb_idVendor=
#deviceinfo_usb_idProduct=
#deviceinfo_usb_serialnumber=

bind_usb_gadget() {
	local gadget="$1"
	local udc_path udc_name udc_function

	for udc_path in /sys/class/udc/*; do
		[ -e "$udc_path" ] || continue

		udc_name="${udc_path##*/}"
		udc_function="$(cat "$udc_path/function" 2>/dev/null)"
		if [ -n "$udc_function" ]; then
			echo "  UDC $udc_name is busy with $udc_function"
			continue
		fi

		if printf '%s' "$udc_name" > "$gadget/UDC"; then
			echo "  Bound $gadget to UDC $udc_name"
			return 0
		fi

		echo "  Could not bind $gadget to UDC $udc_name"
	done

	echo "  No available USB Device Controller"
	return 1
}

setup_usb_network_configfs() {
	local bound_udc

	# See: https://www.kernel.org/doc/Documentation/usb/gadget_configfs.txt
	CONFIGFS=/sys/kernel/config/usb_gadget

	if ! [ -e "$CONFIGFS" ]; then
		echo "  $CONFIGFS does not exist, skipping configfs usb gadget"
		return 1
	fi

	if [ -e "$CONFIGFS/g1" ]; then
		bound_udc="$(cat "$CONFIGFS/g1/UDC" 2>/dev/null)"
		if [ -n "$bound_udc" ]; then
			echo "  $CONFIGFS/g1 is already bound to UDC $bound_udc"
			return 0
		fi

		echo "  $CONFIGFS/g1 exists but is not bound; retrying UDC binding"
		bind_usb_gadget "$CONFIGFS/g1"
		return
	fi

	# Default values for USB-related deviceinfo variables
	usb_idVendor="${deviceinfo_usb_idVendor:-0x1D6B}"   # Linux Foundation
	usb_idProduct="${deviceinfo_usb_idProduct:-0x0103}" # NCM (Ethernet) Gadget
	usb_serialnumber="${deviceinfo_usb_serialnumber:-0123456789}"
	usb_network_function="ncm.usb0"

	echo "  Setting up an USB gadget through configfs"
	# Create an usb gadet configuration
	mkdir $CONFIGFS/g1 || echo "  Couldn't create $CONFIGFS/g1"
	echo "$usb_idVendor" > "$CONFIGFS/g1/idVendor"
	echo "$usb_idProduct" > "$CONFIGFS/g1/idProduct"
	echo 0x0100 > "$CONFIGFS/g1/bcdDevice"
	echo 0x0200 > "$CONFIGFS/g1/bcdUSB"

	# Create english (0x409) strings
	mkdir $CONFIGFS/g1/strings/0x409 || echo "  Couldn't create $CONFIGFS/g1/strings/0x409"

	# shellcheck disable=SC2154
	echo "$deviceinfo_manufacturer" > "$CONFIGFS/g1/strings/0x409/manufacturer"
	echo "$usb_serialnumber" > "$CONFIGFS/g1/strings/0x409/serialnumber"
	# shellcheck disable=SC2154
	echo "$deviceinfo_name" > "$CONFIGFS/g1/strings/0x409/product"

	# Create network function.
	mkdir $CONFIGFS/g1/functions/"$usb_network_function" ||
		echo "  Couldn't create $CONFIGFS/g1/functions/$usb_network_function"

	# Create configuration instance for the gadget
	mkdir $CONFIGFS/g1/configs/c.1 ||
		echo "  Couldn't create $CONFIGFS/g1/configs/c.1"
	echo 250 > $CONFIGFS/g1/configs/c.1/MaxPower
	mkdir $CONFIGFS/g1/configs/c.1/strings/0x409 ||
		echo "  Couldn't create $CONFIGFS/g1/configs/c.1/strings/0x409"
	echo "NCM Configuration" > $CONFIGFS/g1/configs/c.1/strings/0x409/configuration ||
		echo "  Couldn't write configration name"

	# Link the network instance to the configuration
	ln -s $CONFIGFS/g1/functions/"$usb_network_function" $CONFIGFS/g1/configs/c.1 ||
		echo "  Couldn't symlink $usb_network_function"

	# Link the gadget instance to an USB Device Controller. This activates the gadget.
	# See also: https://github.com/postmarketOS/pmbootstrap/issues/338
	bind_usb_gadget "$CONFIGFS/g1"
}

set_usbgadget_ipaddress() {
	local host_ip="${unudhcpd_host_ip:-172.16.42.1}"
	local client_ip="${unudhcpd_client_ip:-172.16.42.2}"
	local interface ifname_path unudhcpd_pid

	ifname_path="$CONFIGFS/g1/functions/ncm.usb0/ifname"
	if [ -r "$ifname_path" ]; then
		interface="$(cat "$ifname_path" 2>/dev/null)"
		[ -e "/sys/class/net/$interface" ] || interface=""
	fi

	# Keep the legacy names for kernels without the ConfigFS ifname attribute.
	if [ -z "$interface" ]; then
		for interface in usb0 eth0; do
			[ -e "/sys/class/net/$interface" ] && break
		done
		[ -e "/sys/class/net/$interface" ] || interface=""
	fi

	if [ -z "$interface" ]; then
		echo "  Could not find an interface to run a dhcp server on"
		echo "  Interfaces:"
		ip link
		return 1
	fi

	echo "  Using interface $interface"
	if ! ip address replace "${host_ip}/16" dev "$interface"; then
		echo "  Could not configure $host_ip on $interface"
		return 1
	fi
	if ! ip link set "$interface" up; then
		echo "  Could not bring $interface up"
		return 1
	fi

	unudhcpd_pid="$(pgrep unudhcpd)"
	if [ -n "$unudhcpd_pid" ]; then
		echo "unudhcpd process already exists, keeping pid $unudhcpd_pid after restoring $interface address"
		return 0
	fi

	echo "Starting unudhcpd service with server ip $host_ip, client ip: $client_ip"
	echo "  Starting the DHCP daemon"
	ip address show dev "$interface" > /var/log/unudhcpd.log
	nohup /usr/bin/unudhcpd -i "$interface" -s "$host_ip" -c "$client_ip" >> /var/log/unudhcpd.log 2>&1 &
	return 0
}
setup_usb_network_configfs
setup_status=$?
set_usbgadget_ipaddress
network_status=$?
[ "$setup_status" -eq 0 ] || exit "$setup_status"
exit "$network_status"
