FROM alpine

RUN apk add --no-cache hostapd dnsmasq iptables
ADD init.sh /bin/init.sh

CMD /bin/sh /bin/init.sh