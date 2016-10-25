#!/bin/bash
# http://wiki.archlinux.org/index.php/Simple_stateful_firewall_HOWTO
#
# Set Up:
IPT=$(which iptables) || exit 1
/etc/rc.d/iptables restart # Restart FW to try to catch module problems.
$IPT -F                    # Flush chains.
$IPT -X                    # Delete rules.
$IPT -P INPUT   DROP       # Block any incoming traffic.
$IPT -P FORWARD DROP       # Same with the traversing one.
$IPT -P OUTPUT  ACCEPT     # We know what we do.
# We Rule:
$IPT -A INPUT -i lo -j ACCEPT # Allow loopback.
$IPT -A INPUT ! -i lo -m state --state ESTABLISHED,RELATED -j ACCEPT # Stateful rule.
$IPT -A INPUT ! -i lo -p tcp --syn -m state --state NEW -m multiport --dports 22,80,139,145,445,6600 -j ACCEPT # New TCP traffic we'll allow.
$IPT -A INPUT ! -i lo -p udp -m state --state NEW -m multiport --dports 69 -j ACCEPT # New TCP traffic we'll allow.
$IPT -A INPUT ! -i lo -p udp -m multiport --dports 67,137:138,1211,2222:2223,17500,57621 -j DROP # Traffic we don't care
$IPT -A INPUT -j LOG -m limit --limit 3/s --limit-burst 8 --log-prefix "DROP " # Log the rest.
# Make the rules static:
/etc/rc.d/iptables save    # Save rules.
/etc/rc.d/iptables restart # Restart FW.
$IPT -vL --line-numbers    # Print Rules.
exit 0                     # Exit gracefully.
