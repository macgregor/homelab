KUBE_LB=192.168.1.220

echo "Configuring firewall rules"

# create cloudflare-proxy chains
iptables -N cloudflare-proxy 2>/dev/null
iptables -N cloudflare-proxy -t nat 2>/dev/null

# add rules to WANPREROUTING/wanin to jump to the cloudflare-proxy chains
if ! iptables -t nat --check WANPREROUTING -j cloudflare-proxy 2>/dev/null; then
  iptables -t nat -A WANPREROUTING -j cloudflare-proxy
fi

if ! iptables --check wanin -j cloudflare-proxy 2>/dev/null; then
  iptables -A wanin -j cloudflare-proxy
fi

# clear old rules
iptables --flush cloudflare-proxy
iptables -t nat --flush cloudflare-proxy

# get cloudflare proxy ip addresses and allow them through the firewall
for i in `curl -s -H 'Cache-Control: no-cache, no-store' https://www.cloudflare.com/ips-v4`; do
  iptables -t nat -A cloudflare-proxy -s $i -p tcp -m tcp --dport 443 -j DNAT --to-destination $KUBE_LB:443
  iptables -A cloudflare-proxy -s $i -d $KUBE_LB -p tcp -m tcp --dport 443 -j ACCEPT
done

# Accept internal ip traffic
if ! iptables --check INPUT -s 192.168.10.0/24 -j ACCEPT 2>/dev/null; then
  iptables -I INPUT -s 192.168.10.0/24 -j ACCEPT
fi

if ! iptables --check INPUT -s 192.168.1.0/24 -j ACCEPT 2>/dev/null; then
  iptables -I INPUT -s 192.168.1.0/24 -j ACCEPT
fi
