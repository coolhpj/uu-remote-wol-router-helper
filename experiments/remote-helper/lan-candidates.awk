# POSIX awk; parse "ip -o -4 addr show scope global" output.
# Emit possible helper LAN identities as "interface|IPv4|netmask".
# Never infer LAN from the default route, never execute code from ip output.
function dotted_ipv4(text, out,   n,i) {
    n=split(text,out,".")
    if(n!=4) return 0
    for(i=1;i<=4;i++) {
        if(out[i] !~ /^[0-9]+$/ || out[i] ~ /^0[0-9]+$/ || length(out[i])>3) return 0
        out[i]+=0
        if(out[i]>255 || out[i]<0) return 0
    }
    return 1
}
function is_lan_name(name) {
    return name == "br-lan" || name == "br0" || name == "lan" || name ~ /^lan[0-9]+$/ || name ~ /^br-lan[.][0-9]+$/
}
function unsafe_name(name) {
    return name ~ /^(lo[0-9]*|wan[0-9]*|pppoe.*|tun.*|tap.*|wg.*|tailscale.*|docker.*|veth.*)$/
}
function address_inside(ip, mask, peer,   i,block,nbase,last) {
    for (i=1;i<=4;i++) {
        block=256-mask[i]
        nbase=int(ip[i]/block)*block
        last=nbase+block-1
        if (peer[i]<nbase || peer[i]>last) return 0
    }
    return 1
}
BEGIN {
    if(!dotted_ipv4(target,target_bytes)) exit 65
}
{
    # iproute2 / BusyBox "ip -o -4 addr show" format, tolerate @peer suffix.
    if($1 !~ /^[0-9]+:$/ || NF<7) next
    iface=$2
    sub(/@.*/, "", iface)
    if (iface !~ /^[A-Za-z0-9_.:-]+$/ || unsafe_name(iface)) next
    if (requested != "" && iface != requested) next
    if (requested == "" && !is_lan_name(iface)) next
    cidr=""
    global_scope=0
    for(i=1;i<NF;i++){
        if($i=="inet") cidr=$(i+1)
        if($i=="scope" && $(i+1)=="global") global_scope=1
    }
    if (!global_scope || cidr=="") next
    n=split(cidr,parts,"/")
    if(n!=2 || parts[2] !~ /^[0-9]+$/) next
    prefix=parts[2]+0
    if (prefix<8 || prefix>30) next
    if(!dotted_ipv4(parts[1],addr)) next
    if (addr[1]==0 || addr[1]==127 || addr[1]>=224 || (addr[1]==169 && addr[2]==254)) next
    for(i=1;i<=4;i++) {
        use=prefix-((i-1)*8)
        if(use<=0) mask[i]=0
        else if(use>=8) mask[i]=255
        else mask[i]=256-2^(8-use)
    }
    if(!address_inside(addr,mask,target_bytes)) next
    print iface "|" parts[1] "|" mask[1]"."mask[2]"."mask[3]"."mask[4]
}
