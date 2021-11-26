# Check if running in privileged mode
if [ ! -w "/sys" ] ; then
    echo "[Error] Not running in privileged mode."
    exit 1
fi

# Default values
true ${INTERFACE:=wlan0}
true ${SUBNET:=192.168.2.0}
true ${AP_ADDR:=192.168.2.1}
true ${SSID:=rp-alpine}
true ${CHANNEL:=6}
true ${WPA_PASSPHRASE:=password}
true ${HW_MODE:=g}
true ${DRIVER:=nl80211}
true ${HT_CAPAB:=[HT40-][SHORT-GI-20][SHORT-GI-40]}
true ${IGNORE_BROADCAST_SSID:=0}

echo "Configuring hostapd..."
cat > "/etc/hostapd/hostapd.conf" <<EOF
interface=${INTERFACE}
driver=${DRIVER}
logger_syslog=-1
logger_syslog_level=2
logger_stdout=-1
logger_stdout_level=2
ssid=${SSID}
hw_mode=${HW_MODE}
channel=${CHANNEL}
max_num_sta=32
rts_threshold=2347
fragm_threshold=2346
macaddr_acl=0
auth_algs=3
ignore_broadcast_ssid=${IGNORE_BROADCAST_SSID}
wpa=2
wpa_passphrase=${WPA_PASSPHRASE}
wpa_key_mgmt=WPA-PSK
# TKIP is no secure anymore
#wpa_pairwise=TKIP CCMP
wpa_pairwise=CCMP
#rsn_pairwise=CCMP
#wpa_ptk_rekey=600
#ieee80211n=1
ht_capab=${HT_CAPAB}
#wmm_enabled=1 
EOF

echo "Configuring dnsmasq..."
cat > "/etc/dnsmasq.conf" <<EOF
interface=${INTERFACE}
dhcp-range=${SUBNET::-1}2,${SUBNET::-1}254,255.255.255.0,12h
EOF

echo "Setting interface ${INTERFACE}"
# Setup interface and restart DHCP service 
ip link set ${INTERFACE} down
ip link set ${INTERFACE} up
ip addr flush dev ${INTERFACE}
ip addr add ${AP_ADDR}/24 dev ${INTERFACE}

# NAT settings
echo "NAT settings ip_dynaddr, ip_forward"
for i in ip_dynaddr ip_forward ; do 
  if [ $(cat /proc/sys/net/ipv4/$i) ]; then
    echo $i already 1 
  else
    echo "1" > /proc/sys/net/ipv4/$i
  fi
done

if [ "${OUTGOINGS}" ] ; then
   ints=${OUTGOINGS//,/ }
   for int in ${ints} ; do
      echo "Setting iptables for outgoing traffics on ${int}..."
      iptables -t nat -D POSTROUTING -s ${SUBNET}/24 -o ${int} -j MASQUERADE > /dev/null 2>&1 || true
      iptables -t nat -A POSTROUTING -s ${SUBNET}/24 -o ${int} -j MASQUERADE

      iptables -D FORWARD -i ${int} -o ${INTERFACE} -m state --state RELATED,ESTABLISHED -j ACCEPT > /dev/null 2>&1 || true
      iptables -A FORWARD -i ${int} -o ${INTERFACE} -m state --state RELATED,ESTABLISHED -j ACCEPT

      iptables -D FORWARD -i ${INTERFACE} -o ${int} -j ACCEPT > /dev/null 2>&1 || true
      iptables -A FORWARD -i ${INTERFACE} -o ${int} -j ACCEPT
   done
else
   echo "Setting iptables for outgoing traffics on all interfaces..."
   iptables -t nat -D POSTROUTING -s ${SUBNET}/24 -j MASQUERADE > /dev/null 2>&1 || true
   iptables -t nat -A POSTROUTING -s ${SUBNET}/24 -j MASQUERADE

   iptables -D FORWARD -o ${INTERFACE} -m state --state RELATED,ESTABLISHED -j ACCEPT > /dev/null 2>&1 || true
   iptables -A FORWARD -o ${INTERFACE} -m state --state RELATED,ESTABLISHED -j ACCEPT

   iptables -D FORWARD -i ${INTERFACE} -j ACCEPT > /dev/null 2>&1 || true
   iptables -A FORWARD -i ${INTERFACE} -j ACCEPT
fi

_term() { 
  echo "Caught SIGTERM signal!" 
  echo "Killing dnsmasq..."
  pkill dnsmasq
  wait $(pidof dnsmasq)
  echo "Killing hostapd..."
  pkill hostapd
  wait $(pidof hostapd)

  if [ "${OUTGOINGS}" ] ; then
    ints=${OUTGOINGS//,/ }
    for int in ${ints} ; do
        echo "Unset iptables on ${INTERFACE}..."
        iptables -t nat -D POSTROUTING -s ${SUBNET}/24 -o ${int} -j MASQUERADE
        iptables -D FORWARD -i ${int} -o ${INTERFACE} -m state --state RELATED,ESTABLISHED -j ACCEPT
        iptables -D FORWARD -i ${INTERFACE} -o ${int} -j ACCEPT
    done
  else
    echo "Unset iptables on all interfaces..."
    iptables -t nat -D POSTROUTING -s ${SUBNET}/24 -j MASQUERADE
    iptables -D FORWARD -o ${INTERFACE} -m state --state RELATED,ESTABLISHED -j ACCEPT
    iptables -D FORWARD -i ${INTERFACE} -j ACCEPT
  fi
  
  echo "Down interface ${INTERFACE}..."
  ip link set ${INTERFACE} down
}

trap _term SIGTERM

echo "Starting dnsmasq server..."
dnsmasq --no-daemon &

echo "Starting HostAP daemon..."
hostapd /etc/hostapd/hostapd.conf &

sleep infinity & wait
