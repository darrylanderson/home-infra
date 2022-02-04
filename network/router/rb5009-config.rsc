###############################################################################
# Description:	Bootstrap config for home RB5009 router
# Credit to:	https://forum.mikrotik.com/viewtopic.php?t=143620
# RouterOS:	7.1.rc6
#
# VLAN Config:
#       BASE = 99
#		HOME = 10
#		IOT = 20
#		GUEST = 30
#
# Port Config:
#       ether1 = WAN
#		ether[2,3,4] = hybrid for unifi APs
#		ether[5,6,7,sfp] = trunk for future switches
#		ether8 = access port for management
#
# To apply:
#   1. Upload file to rb5009
#   2. /system reset-configuration no-defaults=yes skip-backup=yes run-after-reset=rb5009-config.rsc
###############################################################################

# Wait for interfaces to be ready
:local count 0;
:while ([/interface ethernet find] = "") do={
    :if ($count = 30) do={
        :log warning "Unable to find ethernet interfaces";
        /quit;
    }
    :delay 1s; :set count ($count +1);
};

:log info "Starting router configuration script";


#######################################
# Naming
#######################################

# name the device being configured
/system identity set name="MikrotikRB5009"


#######################################
# VLAN Overview
#######################################

# 10 = HOME
# 20 = IOT
# 30 = GUEST
# 99 = BASE (MGMT) VLAN


#######################################
# Bridge
#######################################

# create one bridge, set VLAN mode off while we configure
/interface bridge add name=BR1 protocol-mode=stp vlan-filtering=no


#######################################
# Configure Ports
#######################################

# ingress behavior
/interface bridge port
add bridge=BR1 interface=ether2
add bridge=BR1 interface=ether3
add bridge=BR1 interface=ether4
add bridge=BR1 interface=ether5
add bridge=BR1 interface=ether6
add bridge=BR1 interface=ether7
# Dedicate ether8 as an access port for management
add bridge=BR1 interface=ether8 pvid=99
add bridge=BR1 interface=sfp-sfpplus

# egress behavior
/interface bridge vlan
set bridge=BR1 tagged=BR1,ether2,ether3,ether4,ether5,ether6,ether7,sfp-sfpplus vlan-ids=10
add bridge=BR1 tagged=BR1,ether2,ether3,ether4,ether5,ether6,ether7,sfp-sfpplus vlan-ids=20
add bridge=BR1 tagged=BR1,ether2,ether3,ether4,ether5,ether6,ether7,sfp-sfpplus vlan-ids=30
add bridge=BR1 tagged=BR1,ether2,ether3,ether4,ether5,ether6,ether7,sfp-sfpplus vlan-ids=99

# For Unifi APs, they need to be on hybrid ports as
# they need an untagged vlan for management. This will
# place untagged traffic from those ports on the BASE vlan.
/interface bridge vlan
set bridge=BR1 tagged=ether2,ether3,ether4 [find vlan-ids=99]


#######################################
# IP Addressing & Routing
#######################################

# LAN facing router's IP address on the BASE_VLAN
/interface vlan add interface=BR1 name=BASE_VLAN vlan-id=99
/ip address add address=192.168.0.1/24 interface=BASE_VLAN

# DNS server via Cloudflare, set to cache for LAN
/ip dns set allow-remote-requests=yes servers="1.1.1.2,1.0.0.2"

# WAN facing port with DHCP client to ISP
/ip dhcp-client add interface=ether1


#######################################
# IP Services
#######################################

# Home VLAN interface creation, IP assignment, and DHCP service
/interface vlan add interface=BR1 name=HOME_VLAN vlan-id=10
/ip address add interface=HOME_VLAN address=10.0.10.1/24
/ip pool add name=HOME_POOL ranges=10.0.10.10-10.0.10.254
/ip dhcp-server add address-pool=HOME_POOL interface=HOME_VLAN name=HOME_DHCP disabled=no
/ip dhcp-server network add address=10.0.10.0/24 dns-server=192.168.0.1 gateway=10.0.10.1

# Home VLAN Unifi controller static ip
/ip dhcp-server lease add address=10.0.10.5 mac-address=38:de:ad:00:d0:70

# IoT VLAN interface creation, IP assignment, and DHCP service
/interface vlan add interface=BR1 name=IOT_VLAN vlan-id=20
/ip address add interface=IOT_VLAN address=10.0.20.1/24
/ip pool add name=IOT_POOL ranges=10.0.20.10-10.0.20.254
/ip dhcp-server add address-pool=IOT_POOL interface=IOT_VLAN name=IOT_DHCP disabled=no
/ip dhcp-server network add address=10.0.20.0/24 dns-server=192.168.0.1 gateway=10.0.20.1

# Guest VLAN interface creation, IP assignment, and DHCP service
/interface vlan add interface=BR1 name=GUEST_VLAN vlan-id=30
/ip address add interface=GUEST_VLAN address=10.0.30.1/24
/ip pool add name=GUEST_POOL ranges=10.0.30.10-10.0.30.254
/ip dhcp-server add address-pool=GUEST_POOL interface=GUEST_VLAN name=GUEST_DHCP disabled=no
/ip dhcp-server network add address=10.0.30.0/24 dns-server=192.168.0.1 gateway=10.0.30.1

# Create a DHCP instance for BASE_VLAN. Convenience for administration.
/ip pool add name=BASE_POOL ranges=192.168.0.10-192.168.0.254
/ip dhcp-server add address-pool=BASE_POOL interface=BASE_VLAN name=BASE_DHCP disabled=no
/ip dhcp-server network add address=192.168.0.0/24 dns-server=192.168.0.1 gateway=192.168.0.1



#######################################
# Firewalling & NAT
#######################################

# Use MikroTik's "list" feature for easy rule matchmaking.

/interface list add name=WAN
/interface list add name=VLAN
/interface list add name=BASE

/interface list member
add interface=ether1     list=WAN
add interface=BASE_VLAN  list=VLAN
add interface=HOME_VLAN  list=VLAN
add interface=IOT_VLAN   list=VLAN
add interface=GUEST_VLAN list=VLAN
add interface=BASE_VLAN  list=BASE

# VLAN aware firewall. Order is important.
/ip firewall filter

##################
# INPUT CHAIN
##################
add chain=input action=accept connection-state=established,related,untracked comment="Allow Estab & Related"
add chain=input action=drop connection-state=invalid comment="Drop invalid"
add chain=input action=accept protocol=icmp comment="Accept ICMP"

# Allow VLANs to access router services like DNS, Winbox. Naturally, you SHOULD make it more granular.
add chain=input action=accept in-interface-list=VLAN comment="Allow VLAN"

# Allow BASE_VLAN full access to the device for Winbox, etc.
add chain=input action=accept in-interface=BASE_VLAN comment="Allow Base_Vlan Full Access"

add chain=input action=drop comment="Drop"

##################
# FORWARD CHAIN
##################
add chain=forward action=accept connection-state=established,related comment="Allow Estab & Related"

# Allow HOME_VLAN to access the IOT_VLAN
add chain=forward action=accept connection-state=new in-interface=HOME_VLAN out-interface=IOT_VLAN comment="HOME_VLAN access to IOT_VLAN"

# Allow all VLANs to access the Internet only, NOT each other
add chain=forward action=accept connection-state=new in-interface-list=VLAN out-interface-list=WAN comment="VLAN Internet Access only"

add chain=forward action=drop comment="Drop"

##################
# NAT
##################
/ip firewall nat add chain=srcnat action=masquerade out-interface-list=WAN comment="Default masquerade"


#######################################
# VLAN Security
#######################################

# Hybrid ports for Unifi APs
/interface bridge port
set bridge=BR1 ingress-filtering=yes frame-types=admit-all [find interface=ether2]
set bridge=BR1 ingress-filtering=yes frame-types=admit-all [find interface=ether3]
set bridge=BR1 ingress-filtering=yes frame-types=admit-all [find interface=ether4]

# Trunk ports for switches
set bridge=BR1 ingress-filtering=yes frame-types=admit-only-vlan-tagged [find interface=ether5]
set bridge=BR1 ingress-filtering=yes frame-types=admit-only-vlan-tagged [find interface=ether6]
set bridge=BR1 ingress-filtering=yes frame-types=admit-only-vlan-tagged [find interface=ether7]
set bridge=BR1 ingress-filtering=yes frame-types=admit-only-vlan-tagged [find interface=sfp-spfplus]

# Access port for management server
set bridge=BR1 ingress-filtering=yes frame-types=admit-only-untagged-and-priority-tagged [find interface=ether8]


#######################################
# MAC Server settings
#######################################

# Ensure only visibility and availability from BASE_VLAN, the MGMT network
/ip neighbor discovery-settings set discover-interface-list=BASE
/tool mac-server mac-winbox set allowed-interface-list=BASE
/tool mac-server set allowed-interface-list=BASE


#######################################
# Turn on VLAN mode
#######################################
/interface bridge set BR1 vlan-filtering=yes


#######################################
# Clock
#######################################
/system clock set time-zone-autodetect=no time-zone-name=America/Chicago
/system ntp client set enabled=yes
/system ntp client servers
add address=pool.ntp.org
add address=0.pool.ntp.org
add address=1.pool.ntp.org
add address=2.pool.ntp.org
add address=3.pool.ntp.org


:log info "Configuration script finished";
