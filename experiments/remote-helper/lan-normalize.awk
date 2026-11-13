# Normalize multiline output from "ip -4 addr show" to one-line format.
# Read-only fallback for BusyBox ip variants that lack -o. No shell eval.
BEGIN { current_iface=""; current_idx="" }
{
    if ($1 ~ /^[0-9]+:$/ && NF >= 2) {
        current_idx=$1
        current_iface=$2
        sub(/:$/, "", current_iface)
        sub(/@.*/, "", current_iface)
        if (current_iface !~ /^[A-Za-z0-9_.:-]+$/) current_iface=""
        next
    }
    if ($1=="inet" && current_iface!="" && NF >= 4) {
        global_scope=0
        for(i=1;i<NF;i++) {
            if($i=="scope" && $(i+1)=="global") global_scope=1
        }
        if(global_scope) print current_idx " " current_iface " inet " $2 " scope global " current_iface
    }
}
