gb.substitute()
{
    local seed confdir moddir guestbridgedir socksdir virtiofsdsocksdir vfiodir \
    devlist reslist blacklist bindir mandir ovmfdir cmd i pcidir \
    cmdlist='sed shred perl dirname
    basename cat ls cut bash man mktemp grep egrep env mv sudo
    cp chmod ln chown rm touch head mkdir id find ss file
    modprobe lsmod ip flock groups
    lspci tee umount mount grub-mkconfig ethtool sleep modinfo kill
    lsusb realpath mkinitcpio parted less systemctl
    gpasswd bridge stat date setpci'
    declare -A Devlist=(
    [virtiofsd]=virtiofsd
    [qemu-img]=qemu-img
    [qemu-nbd]=qemu-nbd
    [qemu-system-x86_64]=qemu-system-x86_64
    [socat]=socat 
    )
    cmdlist="${Devlist[@]} $cmdlist"
    for cmd in $cmdlist;do
        i=($(\builtin type -afp $cmd 2>/dev/null))
        if [[ -z $i ]];then
            if [[ -z ${Devlist[$cmd]} ]];then
                reslist+=" $cmd"
            else
                devlist+=" $cmd"
            fi
        fi
        \builtin eval "local ${cmd//-/_}=${i:-:}"
    done
    [[ -z $reslist ]] ||\
    { 
        \builtin printf "%s\n" \
        "$FUNCNAME Require: $reslist"
        return
    }
    [[ -z $devlist ]] ||\
    \builtin printf "%s\n" \
    "$FUNCNAME Optional: $devlist"

    perl_version="$($perl -e 'print $^V')"
    confdir='/srv/kvm/conf/'
    moddir='/etc/modules-load.d/'
    guestbridgedir='/srv/kvm/'
    devicedir='/sys/bus/pci/devices/'
    socksdir='/srv/kvm/socks/'
    vbiosdir='/srv/kvm/vbios/'
    isodir='/srv/kvm/iso/'
    vfiodir='/dev/vfio/'
    bindir='/usr/local/bin/'
    mandir='/usr/local/man/man1'
    ovmfdir='/usr/share/edk2-ovmf/x64/'
    blacklist='/etc/modprobe.d/blacklist.conf'
    seed='${RANDOM}${RANDOM}'
    virtiofsdsocksdir='/run/virtiofsd'
    pcidir='/sys/bus/pci/drivers/'
    [[ -d  $ovmfdir ]] ||\
    \builtin \printf "%s\n" "${FUNCNAME}: Requre: $ovmfdir" 
    declare -a Mod=(
    virtio_balloon
    virtio_blk
    virtio_console
    virtio_crypto
    virtio_gpu
    virtio_input
    virtio_net
    virtio_pci
    virtio_scsi
    virtio_rng
    vhost
    vhost_net
    vhost_vsock
    vhost_scsi
    kvmgt
    vfio_mdev
    vfio_iommu_type1
    vfio_pci
    )
    \builtin \source <($cat<<-SUB

gb.gvt.list()
{
    local help='[pcd addr] [domain num] e.g: /sys/devices/pci0000\:00/0000\:00\:02.0/'
    local gvt_pci=\${1:?\$help}
    local gvt_dom=\${2:?\$help}
}
gb.reset.show()
{
    for iommu_group in \$(find /sys/kernel/iommu_groups/ -maxdepth 1 -mindepth 1 -type d);do
        echo "IOMMU group \$(basename "\$iommu_group")";
        for device in \$(\ls -1 "\$iommu_group"/devices/); do
            if [[ -e "\$iommu_group"/devices/"\$device"/reset ]]; then
                echo -n "[RESET]";
            fi
            echo -n \$'\t';lspci -nns "\$device";
        done
    done
}
gb.py.install()
{
    [[ \${PWD##*/} == 'guestbridge' ]] || return 1 
    local debugging=\${1:-0}
    [[ \$debugging =~ [[:digit:]] ]] || debugging=1
    $sed \
    -e "s;DEBUGGING;\${debugging};" \
    -e "s;GUESTBRIDGEDIR;$guestbridgedir;" \
    -e "s;QEMU-IMG;$qemu_img;g" \
    -e "s;VFIODIR;$vfiodir;" \
    -e "s;VIRTIOFSDSOCKSDIR;$virtiofsdsocksdir;" \
    -e "s;SOCKSDIR;$socksdir;" \
    -e "s;PCIDIR;$pcidir;" \
    src/gb.py > ${bindir}/guestbridge
    $chmod u=rwx,go= $bindir/guestbridge
}
gb.pl.install()
{
    $sed -e "s;\!ENV;\!$env;" -e "s;PERL;$perl;" \
    -e "s;GUESTBRIDGEDIR;$guestbridgedir;" \
    -e "s;QEMU-IMG;$qemu_img;g" \
    -e "s;VFIODIR;$vfiodir;" \
    -e "s;VIRTIOFSDSOCKSDIR;$virtiofsdsocksdir;" \
    -e "s;SOCKSDIR;$socksdir;" \
    -e "s;PCIDIR;$pcidir;" \
    src/gb.pl | $perl src/ptr.pl > ${bindir}/gb
    $chmod u=rwx ${bindir}/gb
}
gb.snapshot.restore()
{
    local vmfile=\${1:?[vm qcow2] [tag name for applying]}
    local tag=\${2:?[tag]}
    $file -b \$vmfile | $grep -q 'QCOW2' || {
        \builtin echo "invalid \$vmfile"
        return 1
    }
    $qemu_img snapshot -a \${tag} \${vmfile}
}
gb.snapshot.cron()
{
    local tag="\$(TZ='Asia/Shanghai' $date +"%Y%m%d%H%M%S")"
    for i in $guestbridgedir/*.qcow2;do
        $file -b \$i| $grep -q 'QCOW2' || continue
        $qemu_img snapshot -c \${tag} \${i}
    done
}
gb.snapshot.delete()
{
    local vmfile=\${1:?[vm qcow2] [tag name for deleting]}
    local tag=\${2:?[tag]}
    $file -b \$vmfile | $grep -q 'QCOW2' || {
        \builtin echo "invalid \$vmfile"
        return 1
    }
    $qemu_img snapshot -d \${tag} \${vmfile}
}
gb.snapshot.list()
{
    local vmfile=\${1:?[vm qcow2]}
    $file -b \$vmfile | $grep -q 'QCOW2' || {
        \builtin echo "invalid \$vmfile"
        return 1
    }
    $qemu_img snapshot -l \${vmfile}
}
gb.snapshot.tag()
{
    local tag=\$(TZ='Asia/Shanghai' $date +"%Y%m%d%H%M%S").snapshot
    local vmfile=\${1:?[vm qcow2]}
    $file -b \$vmfile | $grep -q 'QCOW2' || {
        \builtin echo "invalid \$vmfile"
        return 1
    }
    $qemu_img snapshot -c \${tag} \${vmfile}
}

gb.dirperm()
{
    $sudo $chown -R $USER:kvm $guestbridgedir
    $sudo $chmod --quiet g=rw $socksdir/*   
    $sudo $chmod --quiet gu=r $guestbridgedir/vbios/*
    $sudo $chmod --quiet gu=r $guestbridgedir/ovmf/*_OVMF_VARS.fd
    $sudo $chmod gu=r $guestbridgedir/ovmf/OVMF_VARS.fd
    $sudo $chmod gu=r $guestbridgedir/ovmf/OVMF_CODE.fd
    $sudo $chmod --quiet gu=r $guestbridgedir/iso/*
    $sudo $chmod u=rw,g=r $guestbridgedir/conf/*
    $sudo $chmod u=rw,g=r  $guestbridgedir/*.qcow2
}
gb.checkreset()
{
#    set -x
    local help='[bdf]'
    local bdf=\${1:?\$help}
    bdf="0000:\${bdf}"
    [[ \$UID == 0 ]] || local permit=$sudo
    [[ -f $devicedir/\${bdf}/reset ]] || {
        \builtin echo "not resetable \${bdf}, require manual reset."
        set +x
        return
    }
    \builtin echo "resetable \${bdf}"
    set +x
}
gb.unbind()
{
    local help='[bdf][unbind driver: ehci-pci/vfio-pci]'
    local bdf=\${1:?\$help}
    local unbind=\${2:?\$help}
    bdf="0000:\${bdf}"
    [[ \${UID} == 0 ]] || local permit=$sudo
#    set -x
    [[ -d "${pcidir}/\${unbind}/" ]] || unbind=\${unbind/_/-}
    [[ -d "${pcidir}\${unbind}/" ]] || {
        \builtin echo "non exists: ${pcidir}\${unbind}/"
        return 1
    }
    local unbindpath="${pcidir}/\${unbind}/unbind"
    [[ -e \${unbindpath} ]] && {
        \$permit $chown \$USER:\$USER \${unbindpath}
        \builtin echo "\${bdf}" > \${unbindpath} 2>/dev/null 
        \$permit $chown root:root \${unbindpath}
    }
    $lspci -k -s \${bdf}
    set +x
}
gb.rescan.pciport()
{
    local help='[pcie port path: eg./sys/devices/pci0000:00/0000:00:1c.7]'
    local portpath=\${1:?\$help}
    local rescanpath=\${portpath}/rescan
    [[ \${UID} == 0 ]] || local permit=$sudo
    set -x
    [[ -e \${rescanpath} ]] && {
        \$permit $chown \$USER:\$USER \${rescanpath}
        \builtin echo "1" > \${rescanpath} 2>/dev/null 
        \$permit $chown root:root \${rescanpath}
    }
    set +x
}
gb.pci.capabilities()
{
    $setpci --dumpregs|$less
}
gb.reset.device()
{
    local help='[bdf: NN:NN.N]'
    local bdf=\${1:?\$help}
    bdf="0000:\${bdf}"
    local bdfpath="\$($realpath ${devicedir}\${bdf})"
    [[ \${UID} == 0 ]] || local permit=$sudo
    set -x
    [[ -d \${bdfpath} ]] || {
        \builtin echo "non exist: \${bdfpath}"
        return 1
    }
    local portpath="\$($dirname \${bdfpath})"
    local port=\$($basename \${portpath})
    local removepath=\${bdfpath}/remove
    [[ -e \${removepath} ]] && {
        \$permit $chown \$USER:\$USER \${removepath}
        \builtin echo "1" > \${removepath} 2>/dev/null 
    }
    # BRIDGE_CONTROL Equal to 3e.w
    local on="\$($setpci -s \${port} 3e.w)"
    local off=\$(\builtin printf "%04x" \$(("0x\$on" | 0x40)))
    \$permit $setpci -s \${port} 3e.w=\${off}
    $sleep 0.1
    \$permit $setpci -s \${port} 3e.w=\${on}
    $sleep 0.5
    local rescanpath=\${portpath}/rescan
    [[ -e \${rescanpath} ]] && {
        \$permit $chown \$USER:\$USER \${rescanpath}
        \builtin echo "1" > \${rescanpath} 2>/dev/null 
        \$permit $chown root:root \${rescanpath}
    }
    set +x
}
gb.rebind()
{
    local help='[bdf: NN:NN.N] [unbind driver: ehci-pci/vfio-pci/xhci_hcd/ohci-pci]
    [bind driver: ehci-pci/vfio-pci/xhci_hcd/ohci-pci]'
    local bdf=\${1:?\$help}
    local unbind=\${2:?\$help}
    local bind=\${3:?\$help}
    bdf="0000:\${bdf}"
    [[ \${UID} == 0 ]] || local permit=$sudo
#    set -x
    [[ -d "${pcidir}\${unbind}/" ]] || unbind=\${unbind/_/-}
    [[ -d "${pcidir}\${unbind}/" ]] || {
        \builtin echo "non exists: ${pcidir}\${unbind}/"
        return 1
    }
    [[ -d "${pcidir}\${bind}/" ]] || bind=\${bind/_/-}
    [[ -d "${pcidir}\${bind}/" ]] || {
       \builtin echo "non exists: ${pcidir}\${bind}/"
        return 1
    }
    local idpath="${pcidir}\${bind}/new_id"
    local unbindpath="${pcidir}\${unbind}/unbind"
    local bindpath="${pcidir}\${bind}/bind"
    local id=\$($lspci -s \${bdf} -n |$cut -d' ' -f3)
    [[ -e \${unbindpath} ]] && {
        \$permit $chown \$USER:\$USER \${unbindpath}
        \builtin echo "\${bdf}" > \${unbindpath} 2>/dev/null 
        \$permit $chown root:root \${unbindpath}
    }
    [[ -e \${idpath} ]] && {
        \$permit $chown \$USER:\$USER \${idpath} 
        \builtin echo "\${id/:/ }" > \${idpath} 2> /dev/null 
        \$permit $chown root:root \${idpath}
    }
    [[ -e \${bindpath} ]] && {
        \$permit $chown \$USER:\$USER \${bindpath}
        \builtin echo "\${bdf}" > \${bindpath} 2> /dev/null 
        \$permit $chown root:root \${bindpath}
    }
    $lspci -s \${bdf} -k
    set +x
}
gb.bind()
{
    local help='[bdf][bind driver: ehci-pci/ohci-pci/xhci-hcd/vfio-pci/i801_smbus]'
    local bdf=\${1:?\$help}
    local bind=\${2:?\$help}
    bdf="0000:\${bdf}"
    [[ \$($id -u) == 0 ]] || local permit=$sudo
    [[ -d "${pcidir}\${bind}/" ]] || bind=\${bind/_/-}
    [[ -d "${pcidir}\${bind}/" ]] || {
       \builtin echo "non exists: ${pcidir}\${bind}/"
        return 1
    }
    local idpath="${pcidir}\${bind}/new_id"
    local bindpath="${pcidir}/\${bind}/bind"
    local id=\$($lspci -s \${bdf} -n |$cut -d' ' -f3)
    [[ -e \${idpath} ]] && {
        \$permit $chown \$USER:\$USER \${idpath} 
        \builtin echo "\${id/:/ }" > \${idpath} 2>/dev/null 
        \$permit $chown root:root \${idpath}
    }
    [[ -e \${bindpath} ]] && {
        \$permit $chown \$USER:\$USER \${bindpath}
        \builtin echo "\${bdf}" > \${bindpath} 2>/dev/null
        \$permit $chown root:root \${bindpath}
    }
    $lspci -s \${bdf} -k
}

gb.query.mac()
{
    local i nic=\${1:?[nic name]}
    declare -a Ip=(\$($ip -o link show \${nic}))
    for ((i=\${#Ip[@]} - 1; i > 0 ; i--));do
        $egrep -q -w "permaddr|link/ether" <<<\${Ip[i]} || continue
        echo \${Ip[((i + 1))]}
        return
    done
}
gb.virtiofsd.stop()
{
    a.perm ${virtiofsdsocksdir} root:kvm g=rwx,o= g=rw,o=
    local i pid name vmsocks="\$($ls -A ${socksdir})"
    for i in \$($ls -A ${virtiofsdsocksdir});do
        name=\${i%%-@*}
        name=\${name##*.}
        $grep -q -w \$name <<<\$vmsocks && continue
#    set -x
        [[ "\${i}" =~ "pid" ]] && {
            $sudo $kill -s SIGKILL \$(<"${virtiofsdsocksdir}/\${i}")
            $rm -f "${virtiofsdsocksdir}/\${i}"
            continue
        }
        [[ "\${i}" =~ "sock" ]] && {
            $rm -f "${virtiofsdsocksdir}/\${i}"
            continue
        }
    done 
    set +x
}
gb.virtiofsd.config()
{
    local i guestname=\${1:?\${FUNCNAME}:[guest host name/imagefile/configfile]}
    local socketname socketpath tmpfile tag
    guestname=\${guestname##*/}
    guestname=\${guestname%.*}
    [[ -r ${confdir}/\${guestname} ]] || { set +o xtrace; return 1; }
    declare -a Sharedir=(\$($egrep "virtiofsd" ${confdir}/\${guestname}|\
    $sed "s;^.*virtiofsd/\${guestname}-\(.*\).sock.*\$;\1;"))
#    set -x
    for i in \${Sharedir[@]};do
        [[ -n "\$i" ]] || continue
        socketname="\${guestname}-\${i}.sock"
        socketpath="${virtiofsdsocksdir}/\${socketname}"
        [[ -S \${socketpath} ]] && continue
        i=\${i//@//}
        [[ -d \${i} ]] || continue
        tmpfile=/var/tmp/${seed}
        tag=\${i%/}
        tag=\${tag##*/}
        $cat <<-VIRTIOFSDSTART > \${tmpfile}
#!$env $bash
    \builtin exec $virtiofsd --syslog \
    --socket-path="\${socketpath}" \
    --thread-pool-size=6 \
    -o source=\${i} &
VIRTIOFSDSTART
        $chmod u=rwx \${tmpfile}
        $sudo \${tmpfile}
        $rm -f \${tmpfile}
        gb.perm ${virtiofsdsocksdir} root:kvm g=rwx g=rw
    done
    $sleep 2
    set +x
}
gb.powerdown()
{
    local vm=\${1:?[hostname]}
    gb.socks \$vm system_powerdown
}
gb.vmreconfig()
{
    local config=\${1:?[vm config file e.g: vm/hostname]}
    local name=\${config##*/}
    local tmpfile=/tmp/${seed}
    $sed -e "s;^#.*\$;;g" -e "/^\$/d" \$config > \$tmpfile
    $mv -f \$tmpfile $confdir/\$name
    $chown -f $USER:kvm $confdir/\$name
    $chmod -f ug=r $confdir/\$name
}
gb.lock()
{
    local cmd fun=\${@:?[function name]}
    if [[ \${UID} != 0 ]];then
        cmd=$sudo
        \$cmd $chown root:adm /run/lock
        \$cmd $chmod ug=rwx,o=rx /run/lock
    fi
    (
#        set -o xtrace
        $flock --nonblock 9 || return
        \builtin \trap "gb_delocate" SIGHUP SIGTERM SIGINT
        gb_delocate()
        {
            [[ -a /var/lock/gb ]] && \${cmd} $rm -f /var/lock/gb
            \builtin trap - SIGHUP SIGTERM SIGINT
            \builtin unset -f gb_delocate
            \builtin set +o xtrace
        }
        \$fun
        gb_delocate 
    ) 9>/var/lock/gb
}
gb.bootgpu()
{
    local lspci="\$($lspci -vmk)"
    [[ \$($id -u) == 0 ]] || local cmd=$sudo
    declare -a Res=(\$($perl - "\${lspci}" <<'GBSWAPGPU' 
use $perl_version;
use warnings;
use strict;
#use Data::Dumper;
my \$bdf='(?:[a-z0-9][a-z0-9]:[a-z0-9][a-z0-9].[a-z0-9])';
my @Res = ('none','none','none');
\$_ = \${ARGV[0]};
foreach(split(/(?:\n){2}/)){
    next if(!m;Class:\s*VGA\s+?;);
    foreach(split(/\n/)){
        if(m;Device:\s*(\$bdf)\$;){
            \$Res[0] = "\$1";
        }elsif(m;Driver:\s*([^\s]+)\$;){
            \$Res[1] = "\$1"; 
        }elsif(m;Module:\s*([^\s]+)\$;){
            \$Res[2] = "\$1";
        }
    }
    say join('@', @{Res});
    @Res = ('none','none','none');
}
GBSWAPGPU
))
#    set -o xtrace
    local i
    declare -a Entry
    for i in \${Res[@]};do
        Entry=(\${i//@/ })
        file="$pcidir/\${Entry[2]}/0000:\${Entry[0]}/boot_vga"
        [[ -r \${file} && "\$($cat \$file)" == 1 ]] && return
        gb.loadmod \${Entry[2]} 
        if [[ \${Entry[1]} =~ 'none' ]];then
            gb.bind \${Entry[1]} \${Entry[2]}
            continue
        fi
        [[ \${Entry[1]} =~ \${Entry[2]} ]] && continue
        gb.rebind \${Entry[@]}
        return
    done
    set +o xtrace
}
gb.croninstall()
{
    gb.cronuninstall
    $sudo $cp service /lib/systemd/system/gb.service
    $sudo $chmod 0644 /lib/systemd/system/gb.service
    $sudo $cp timer /lib/systemd/system/gb.timer
    $sudo $chmod 0644 /lib/systemd/system/gb.timer
    $sudo $ln -s /lib/systemd/system/gb.timer \
        /lib/systemd/system/timers.target.wants/gb.timer
}
gb.cronuninstall()
{
    $sudo $rm -f /lib/systemd/system/gb.service
    $sudo $rm -f /lib/systemd/system/gb.timer
    $sudo $rm -f /lib/systemd/system/timers.target.wants/gb.timer
    $sudo $rm -f /var/lib/systemd/timers/stamp-gb.timer
}
gb.enable()
{
    $sudo $systemctl enable gb.timer
}
gb.start()
{
    $sudo $systemctl start gb.timer
    gb.timer
}
gb.stop()
{
    $sudo $systemctl stop gb.timer
    gb.timer
}
gb.disable()
{
    $sudo $systemctl disable gb.timer
    gb.timer
}
gb.mask()
{
    $sudo $systemctl mask gb.timer
    gb.timer
}
gb.unmask()
{
    $sudo $systemctl unmask gb.timer
    gb.timer
}
gb.reload()
{
    $sudo $systemctl daemon-reload
}
gb.units()
{
    $sudo $systemctl list-units
}
gb.timer()
{
    $sudo $systemctl list-timers --all
}
gb.fun2script()
{
#    set -o xtrace
    local script="${bindir}/gb.cron"
    local tmpfile=/tmp/\$RANDOM
    $rm -f \$script
    $cat <<-GBCRON > \$tmpfile 
#!$env $bash
\$(\builtin declare -f gb.lock)
\$(\builtin declare -f gb.bootgpu)
\$(\builtin declare -f gb.bind)
\$(\builtin declare -f gb.loadmod)
\$(\builtin declare -f gb.rebind)
\$(\builtin declare -f gb.rebind2module)
\$(\builtin declare -f gb.cron)
gb.lock gb.cron >/dev/null
GBCRON
    $chown -f $USER:adm \$tmpfile
    $chmod -f ug=rx,o= \$tmpfile
    $mv -f \$tmpfile \$script
#    set +o xtrace
}
gb.cron()
{
    local fb socket guestname binding
    [[ \$($id -u) == 0 ]] || return
#    set -o xtrace
    for socket in ${socksdir}/*;do
        [[ -S \${socket} ]] || continue
        guestname=\${socket##*/}
        $socat - UNIX-CONNECT:\${socket} <<< 'info name' 2>/dev/null && continue
        [[ -r ${confdir}/\${guestname} ]] || continue
        gb.rebind2module $confdir/\${guestname} || continue 
        $rm -f \${socket}
        $rm -f ${virtiofsdsocksdir}/\${guestname}-*
        $rm -f ${virtiofsdsocksdir}//${virtiofsdsocksdir////.}\${guestname}-*
    done
    # We trust previous procedure rebind VGA correct
    # Only do the following when booting host OS
    [[ -n \$guestname ]] && return
    for fb in /dev/fb*;do
        [[ -c \$fb ]] && return
        gb.bootgpu
        return
    done
#    set +o xtrace
}
gb.lspci()
{
    $lspci -vmk|$less
}
gb.shutdown()
{
    local name=\${1:?[guest vm hostname]}
    [[ -r ${socksdir}/\${name} ]] || return
    [[ -r $confdir/\${name} ]] || return
    $socat - UNIX-CONNECT:${socksdir}/\${name} <<< 'system_powerdown' || return
    $sleep 5
    gb.rebind2module $confdir/\${name} || return
    $socat - UNIX-CONNECT:${socksdir}/\${name} <<< 'info name' 2>/dev/null && return 1
    $sudo $rm -f ${socksdir}/\${name}
}
gb.capabilities()
{
    local bdf=\${1:?[bdf: 00:0X.Y]}
    $sudo lspci -v -s \${bdf}
}
gb.telnetmonitor()
{
    local guestname=\${1:?[guestname][cmd to guest]}
    \builtin shift
    local cmd=\${@:?[cmd to guest]}
    local name i ports="\$($ss --tcp --listen --numeric|\
    $egrep --only-matching "127.0.0.1:[[:digit:]]+"|\
    $cut -d':' -f2)"
    for i in \$ports;do
        (\builtin echo "info name";$sleep 0.3)|\
        $telnet 127.0.0.1 \${i}|$egrep -q -w "\${guestname}"
        [[ \$? != 0 ]] && continue
        (\builtin echo "\${cmd}";$sleep 0.3)|\
        $telnet 127.0.0.1 \${i}
        return
    done   
}
gb.usb.iommu()
{
    local usb_ctrl pci_path    
    for usb_ctrl in \$($find /sys/bus/usb/devices/usb* -maxdepth 0 -type l); do
        pci_path="\$($dirname "\$($realpath "\${usb_ctrl}")")"
        \builtin echo "Bus \$(<"\${usb_ctrl}/busnum") \
        \$($basename \$pci_path) \
        (IOMMU group \$($basename \$($realpath \$pci_path/iommu_group)))"
        $lsusb -s "\$(<"\${usb_ctrl}/busnum"):"
        \builtin echo
    done
}
gb.mount.qcow2()
{
    local file=\${1:?[qcow2 file]}
    $egrep -q 'nbd' <<<\$($lsmod) || $sudo $modprobe nbd max_part=63
    $sudo $qemu_nbd -c /dev/nbd0 \${file}
    $sudo parted /dev/nbd0 print
   \builtin printf "%s\n" "use: mount /dev/nbd0pX /mnt/X | mount.ufs | mount -t ufs -o ufstype= /dev/nbd0pX /mnt/X"
}
gb.unmount.qcow2()
{
    local mp=\${1:?[mp] unmount and/or disconnect /dev/nbd0}
    mp=\$($realpath \$mp)
    $sudo umount -fq \$mp
    $sudo $qemu_nbd -d /dev/nbd0
    $sudo $modprobe --remove --verbose nbd
}
gb.iommu()
{
    declare -a Iommu=("\$($find /sys/kernel/iommu_groups/*/devices/*)")
    declare -a Pci=("\$($lspci -nn)")
    $perl - "\${Iommu[@]}" "\${Pci[@]}" <<'GBIOMMU'|$less 
use $perl_version;
use warnings;
use strict;
#use Data::Dumper;
my \$pattern='([a-z0-9][a-z0-9]:[a-z0-9][a-z0-9].[a-z0-9])';
my %Group = ();
my %Pci = ();
my %Res = ();
\$_ = \$ARGV[0];
s{
    /sys/kernel/iommu_groups/([0-9]+)/devices/0000:\${pattern}\n*
}{
    \$Group{\$2} = "\$1";
}mexg;
\$_ = \$ARGV[1];
s{
    \${pattern}\s+([^:]+)(:)\s+(.*)\n*
}{
    \$Pci{\$1} = "\$2\$3\n\$4";
}mexg;
foreach( keys %Group){
    \$Res{\$Group{\$_}} .= "[\$_] \$Pci{\$_}\n";
}
foreach( sort keys %Res)
{
    say "iommu group: \$_ \n\$Res{\$_}";
}
#say Dumper(\\%Pci);
GBIOMMU
}
gb.run()
{
    local help="\${FUNCNAME}:[guestimage file] [nicname] [optional debug flag:1|0]"
    gb.virtiofsd.config \${@:?\${help}} || return 
    gb.lock _gb.run \${@:?\${help}}
}
_gb.run()
{
    local guestimg=\${1:?[guestimage][nicname]}
    local guestname=\${guestimg##*/}
    guestname=\${guestname%.*}
    local guestcfg=${confdir}/\${guestname}
    local nic=\${2:?[nicname]}
    local bridge=\$(gb.query.mac \${nic})
    bridge=\${bridge//:/}
    local debug=\${3}
    \builtin shopt -s extdebug
    [[ "\${debug}" -eq 1 ]] && debug="set -o xtrace" || \builtin unset -v debug
    \builtin \trap "gb_guest_delocate" SIGHUP SIGTERM SIGINT
    gb_guest_delocate()
    {
        [[ -r \${tmpfile} ]] && $shred -fu \${tmpfile}
        builtin unset -f gb_guest_delocate
        builtin trap - SIGHUP SIGTERM SIGINT
        \builtin set +o xtrace
        \builtin shopt -u extdebug
    }
    \${debug}
    $groups | $grep -q -w "kvm" || return
    [[ -f \${guestcfg} ]] || return
    [[ -a \${guestimg} ]] || return
    [[ -c $vfiodir/vfio ]] || return
    [[ -S ${socksdir}/\${guestname} ]] && return
    local tmpfile=/var/tmp/\${RANDOM}
    declare -a Config=(\$($sed -e "s;GUESTIMG;\${guestimg};" \${guestcfg})) 
    gb.tap bridge nic guestname || { gb_guest_delocate; return; }
    gb.rebind2config \${guestcfg} 
    gb.perm /dev/vfio root:kvm g=rwx g=rw
    $cat<<KVMGUEST> \${tmpfile}
#!$env $bash
    \builtin exec $qemu_system_x86_64 -chroot /var/tmp/ -runas kvm \${Config[@]} &
#    \builtin exec $qemu_system_x86_64 \${Config[@]} &
KVMGUEST
    $chown :kvm \${tmpfile}
    $chmod ug=rx \${tmpfile}
    $sudo \${tmpfile}
    $sleep 2
    if [[ -S ${socksdir}/\${guestname} ]];then
        $sudo $chown kvm:kvm ${socksdir}/\${guestname}
        $sudo $chmod ug=rw ${socksdir}/\${guestname}
    fi
    gb_guest_delocate
}
gb.tap()
{
    ## 1,bridge 2,nic 3,guestname
    gb.bridge.add "\${!1}" "\${!2}" || return 1
    gb.tap.add "tap_\${!3}"
    gb.tap2bridge tap_\${!3} \${!1}
}
gb.remove()
{
   \builtin echo 1 | $sudo $tee /sys/bus/pci/devices/0000:00:01.0/remove
   \builtin echo 1 | $sudo $tee /sys/bus/pci/devices/0000:00:01.1/remove
   \builtin echo 1 | $sudo $tee /sys/bus/pci/rescan
}
gb.help()
{
    local input=\${@}
    input=\${input:+"\$input help"}
    input=\${input:-"-h"}
    input=\${input#-}
    input=-\$input
    $qemu_system_x86_64 \$input|le
}
gb.listguests()
{
    declare -a Res=(\$($ls $socksdir))
    \builtin printf "%s\n" "\${Res[@]/.sock/}"
}
gb.rebind2module()
{
    local help="[vm/hostname config file/BASH indirect expansion]"
    local config=\${1:?\$help}
    declare -a Blacklist
    $file \$config|$egrep -q text || return
    [[ -r $blacklist ]] && \
    Blacklist=("\$($egrep blacklist $blacklist|$cut -d' ' -f2-)")
    declare -a Config=("\$(<"\$config")")
    declare -a Lspci=("\$($lspci -vmk)")
    declare -a Rebind=(\$($perl - "\${Config[@]}" \
    "\${Lspci[@]}" "\${Blacklist[@]}" <<'GBREBIND2MODULE' 
use $perl_version;
use warnings;
use strict;
#use Data::Dumper;
my \$pattern='([a-z0-9][a-z0-9]:[a-z0-9][a-z0-9].[a-z0-9])';
my %Wish = ();
my %Real = ();
my %Module= ();
my %Black = ();
my \$res = '';
my \$bdf = '';
foreach(split(/\s/,\$ARGV[2])){
    \$Black{\$_} = \$_;
}
\$_ = \$ARGV[0];
s{
    ^-device\s+(.+)\s*?,\s*?host="{0,1}?\${pattern}"{0,1}?,{0,1}?\n*?
}{
     \$Wish{\$2} = "\$1" if(!defined \$Black{\$1});
}mexg;
\$_ = \$ARGV[1];
foreach(split(/(?:\n){2}/)){
    foreach(split(/\n/)){
        if(m;Device:\s*(\$pattern)\$;){
            \$bdf = "\$1";
        }elsif(m;Driver:\s*([^\s]+)\$;){
            \$Real{\$bdf} = "\$1"; 
        }elsif(m;Module:\s*([^\s]+)\$;){
            \$Module{\$bdf} = "\$1";
        }
    }
}
foreach(keys %Wish){
    if(!defined \$Real{\$_}){
        \$_ = "gb.loadmod \$Module{\$_} && gb.bind \$_ \$Module{\$_}";
        s/\s/@/g;
        say;
        next;
    }
    next if(\$Real{\$_} =~ \$Module{\$_});
    \$_ = "gb.loadmod \$Module{\$_} && gb.rebind \$_ \$Real{\$_} \$Module{\$_}";
    s/\s/@/g;
    say;
}
#say Dumper(\\\%Module);
GBREBIND2MODULE
))
    set -o xtrace
    local i
    for i in \${Rebind[@]};do
#        echo "\${i//@/ }"
        \builtin eval "\${i//@/ }"
    done
    set +o xtrace
}
gb.deviceid()
{
    local bdf=\${1:?[bdf]}
    $lspci -n|$egrep \$bdf | $cut -d' ' -f3
}
gb.rebind2config()
{
    local help="[vm/hostname config file/BASH indirect expansion]"
    local config=\${1:?\$help}
    declare -a Blacklist
#    set -o xtrace
    $file \$config|$egrep -q text || return
    # Just precaution that not load these moudule during pass through.
    [[ -r $blacklist ]] && \
    Blacklist=("\$($egrep blacklist $blacklist|$cut -d' ' -f2-)")
    declare -a Config=("\$(<"\$config")")
    declare -a Lspci=("\$($lspci -vmk)")
    declare -a Rebind=(\$($perl - "\${Config[@]}" \
    "\${Lspci[@]}" "\${Blacklist[@]}" <<'GBREBIND2CONFIG' 
use $perl_version;
use warnings;
use strict;
#use Data::Dumper;
my \$pattern='([a-z0-9][a-z0-9]:[a-z0-9][a-z0-9].[a-z0-9])';
my \$bdf = '';
my %Wish = ();
my %Real = ();
my %Module= ();
my %Black = ();
foreach(split(/\s/,\$ARGV[2])){
    \$Black{\$_} = \$_;
}
\$_ = \$ARGV[0];
s{
    ^-device\s+(.+)\s*?,\s*?host="{0,1}?\${pattern}"{0,1}?,{0,1}?\n*?
}{
    \$Wish{\$2} = "\$1" if(!defined \$Black{\$1});
}mexg;
\$_ = \$ARGV[1];
foreach(split(/(?:\n){2}/)){
    foreach(split(/\n/)){
        if(m;Device:\s*(\$pattern)\$;){
            \$bdf = "\$1";
        }elsif(m;Driver:\s*([^\s]+)\$;){
            \$Real{\$bdf} = "\$1"; 
        }elsif(m;Module:\s*([^\s]+)\$;){
            \$Module{\$bdf} = "\$1";
        }
    }
}
foreach(keys %Wish){
    if(!defined \$Real{\$_}){
        \$_ = "gb.loadmod \$Wish{\$_} && gb.bind@\$_ \$Wish{\$_}";
        s/\s/\@/g;
        say;
        next;
    }
    next if(\$Wish{\$_} =~ \$Real{\$_});
    if(\$Real{\$_} =~ "amdgpu|nouveau"){
        \$_ = "gb.rebind \$_ \$Real{\$_} \$Wish{\$_} && gb.unloadmod \$Real{\$_}";
        s/\s/\@/g;
        say;
        next;
    }
    \$_ = "gb.rebind \$_ \$Real{\$_} \$Wish{\$_}";
    s/\s/\@/g;
    say;
    next;
}
GBREBIND2CONFIG
))
#    set -o xtrace
    local i
    for i in \${Rebind[@]};do
#        echo "\${i//@/ }"
        \builtin eval "\${i//@/ }"
    done
    set +o xtrace
}
gb.iommu()
{
    declare -a Iommu=("\$($find /sys/kernel/iommu_groups/*/devices/*)")
    declare -a Pci=("\$($lspci -nn)")
    $perl - "\${Iommu[@]}" "\${Pci[@]}" <<'GBIOMMU'|$less 
use $perl_version;
use warnings;
use strict;
#use Data::Dumper;
my \$pattern='([a-z0-9][a-z0-9]:[a-z0-9][a-z0-9].[a-z0-9])';
my %Group = ();
my %Pci = ();
my %Res = ();
\$_ = \$ARGV[0];
s{
    /sys/kernel/iommu_groups/([0-9]+)/devices/0000:\${pattern}\n*
}{
    \$Group{\$2} = "\$1";
}mexg;
\$_ = \$ARGV[1];
s{
    \${pattern}\s+([^:]+)(:)\s+(.*)\n*
}{
    \$Pci{\$1} = "\$2\$3\n\$4";
}mexg;
foreach( keys %Group){
    \$Res{\$Group{\$_}} .= "[\$_] \$Pci{\$_}\n";
}
foreach( sort keys %Res)
{
    say "iommu group: \$_ \n\$Res{\$_}";
}
#say Dumper(\\%Pci);
GBIOMMU
}
gb.socks()
{
    local help="[hostname/socket file][monitor cmds eg:info name/quit]"
    local name=\${1:?\$help}
    \builtin shift
    local cmd=\${@:?[QEMU monitor commands eg: info name]}
#    set -x
    [[ -S "${socksdir}/\$name" ]] && name="${socksdir}/\$name"
    [[ -S \$name ]] || return
    [[ "\$($stat -c %G \$name)" == 'kvm' ]] || {
        $sudo $chown :kvm \$name
        $sudo $chmod g=rw \$name
    }
    $socat - UNIX-CONNECT:\$name <<<"\${cmd}"
    set +x
}

gb.info()
{
    $less<<-KVMINFO
    install qemu-headless
    # qemu-system-x86_64 -device vfio-pci,help
    # cpu support
    grep vmx /proc/cpuinfo

    # Kernel support y or m
    zgrep CONFIG_KVM /proc/config.gz

    #para-virtual device support y or m
    zgrep VIRTIO /proc/config.gz

    # find modules
    inside /usr/lib/modules/

    # avaliable modules
    list /lib/modules/
    
    # kernel module loaded ?
    lsmod |egrep kvm|virtio
    gb.loadmodall
    gb.reconfig
    gb.dirperm

    ##########################################
    # Only for pci pass through via IOMMU/Intel VT-d/Amd-Vi
    ##########################################
    #enable hugepages
    gb.hugepages
    # Enable IOMMU
    enable VT-D in BIOS.
    gb.grub
    # Non-root pci passthrough by allowing rising kvm user lock memory limits.
    gb.limits

    # show pci device id
    lspci -vvn

    # bind vfio-pci to pci device as kernel module.
    cat vm/hostname/vfio.conf
    output: options vfio-pci ids=9809:1301
    gb.modprobconfig

    # load module precedence.
    gb.mkinitcpio

    # Restart Host Computer
    dmesg|egrep IOMMU
    # List iommu group
    gb.iommu

    # Bind devices with/without pass through
    # in the same iommu group
    # Verify binded vfio-pci devices
    dmesg | egrep -i vfio_pci
    # Output: vfio_pci: add [9809:1301]
    lspci -vmk  
    Driver: vfio-pci

    # Find out BDF of the Nic for pass through
    gb.iommu |egrep "Intel Corporation 82579"
    # Output BDF : 00:18.0 Ethernet controller 
    # Configure and install guest config file
    gb.vmreconfig vm/guestname
    
    # install gb.py script
    gb.py.install

    # Start guest vm
    # this script will first create a snapshot tag for this vm
    # and will not start vm if the /run/lock/backup exits.
    # the /run/lock/backup indicate the vm backup process is in progress.
    gb [guestimage file]

    # Interact with QEMU monitor
    gb.socks [guestname] help
    gb.socks [guestname] [info name|system_powerdown|quit]
    # Shutdown guest and rebind devices passed through
    gb.shutdown [guestname]

    # If guest don't boot direct into OS but stay on UEFI shell
    # grub.reconfig inside guest OS.

    # install systemd cron service.
    # enable auto release devices passed through to guest.
    gb.croninstall
    gb.enable
    gb.start
    gb.timer

    # Mount/Unmount Modify qcow2
    gb.mount.qcow2
    # Mount partitions and chroot into it.

    # In case device can't take back/reset, install package
    vendor-reset-dkms-git 

    # Leave qemu monitor inside telnet
       ^]
       telnet> quit
    # Guest audio enable MSI Capabilities
    # When using vnc, network name changes

    # Resize filesystem and partition
    # boot arch.iso with vm.qcow2
    cfdisk /dev/sdX
    resize partition
    e2fsck -f /dev/sdXY
    resize2fs /dev/sdXY SIZE
KVMINFO
}

gb.limits()
{
    local config=\${1:?[vm/hostname security limits.conf]}
    $sed "s;USER;\${USER};g" \${config} |$sudo $tee /etc/security/limits.conf
}
gb.grub()
{
    local config=\${1:?[vm/hostname grub default config file]}
    $sudo $cp \${config} /etc/default/grub
    $sudo $grub_mkconfig -o /boot/grub/grub.cfg
}
gb.listmod()
{
    \builtin echo ${Mod[@]}
}
gb.loadmodall()
{
    $sudo $modprobe --verbose --all ${Mod[@]}
    $lsmod|$egrep "virtio|vhost"
}
gb.loadmod()
{
    local mod=\${1:?[module to load]}
    [[ \${UID} == 0 ]] || local cmd=$sudo
    \$cmd $modprobe \$mod
}
gb.unloadmod()
{
    local mod=\${1:?[module for unload]}
    $sudo $modprobe --remove \$mod
}
gb.modprobeconfig()
{
    local dir=\${1:?[directry path]}
    if [[ -r \$dir/vfio.conf ]];then
        $sudo $cp \$dir/vfio.conf /etc/modprobe.d/vfio.conf
        $sudo $chmod u=rw,go=r /etc/modprobe.d/vfio.conf
    fi
    if [[ -r \$dir/blacklist.conf ]];then
        $sudo $cp \$dir/blacklist.conf /etc/modprobe.d/blacklist.conf
        $sudo $chmod u=rw,go=r /etc/modprobe.d/blacklist.conf
    fi
    [[ -r \$dir/mkinitcpio.conf ]] &&\
    gb.mkinitcpio \$dir/mkinitcpio.conf
}
gb.mkinitcpio()
{
    local conf=\${1:?[mkinitcpio.conf]}
    $sudo $cp \$conf /etc/mkinitcpio.conf 
    $sudo $chmod u=rw,go=r /etc/mkinitcpio.conf
    $sudo $mkinitcpio && $sudo $mkinitcpio -g /boot/initramfs-linux.img
}
gb.unloadmodall()
{
    $sudo $modprobe --remove --verbose --all ${Mod[@]}
    $lsmod|$egrep "virtio|vhost"
}
gb.resize.img()
{
    local image=\${1:?[image][+/-size]}
    local size=\${2:?[+/-size]}
    local format='qcow2'
    [[ -f \$image ]] || return
    $qemu_img resize \$image \${size}
    $qemu_img info \$image
}
gb.create.img()
{
    local help='[name] [size] [opt: format raw/qcow2 def:qcow2]
    [opt: dir def: $guestbridgedir]'
    local name=\${1:?\$help}
    local size=\${2:?\$help}
    local format=\${3:-qcow2}
    local dir=\${4:-$guestbridgedir}
    [[ -d \$dir ]] || $sudo $mkdir -p \$dir 
    $qemu_img create -f \${format} \$dir/\${name}.\${format} \${size}
    $sudo $chown \$USER:kvm \$dir/\${name}.\${format}
    $sudo $chmod ug=rw \$dir/\${name}.\${format}
    $qemu_img info \$dir/\${name}.\${format}
}
gb.convert.img()
{
#    set -x
    declare -A Format=( img raw )
    local help='[in image file] [out image file]'
    local infile=\${1:?\$help}
    local outfile=\${2:?\$help}
    informat=\${infile##*.}
    outformat=\${outfile##*.}
    [[ -n \${Format[\$informat]} ]] && informat=\${Format[\$informat]}
    [[ -n \${Format[\$outformat]} ]] && outformat=\${Format[\$outformat]}
    $qemu_img convert -f \${informat} -O \${outformat} \${infile} \${outfile}
    set +x
}
gb.img.info()
{
    local img=\${1:?[img]}
    $qemu_img info \${img}
}
gb.tap.add()
{
    local name=\${1:?[tap name e.g:tap0]}
    $ip link|$egrep -w "\${name}:" >/dev/null && return 0
    $sudo $ip tuntap add dev \${name} mode tap user \${USER}
    $sudo $ip link set dev \${name} up
    $ip tap
}
gb.tap2bridge()
{
    local tap=\${1:?[tap name e.g:tap0][bridge name e.g:brX]}
    local br=\${2:?[bridge name]}
    $ip link|$egrep -w "\${tap}:" >/dev/null || return
    $ip link|$egrep -w "\${br}:" >/dev/null || return
    $sudo $ip link set \${tap} master \${br}
}
gb.reconfig()
{ 
    local prefix
    [[ \$($basename \${PWD}) == guestbridge ]] || return
    gb.resetconfig
    $sudo $mkdir -p $mandir
    $sudo $chmod 0755 $mandir
    $sudo $cp doc/guestbridge.1 \
    $mandir/guestbridge.1
    $sudo $chmod 0644 $mandir/guestbridge.1 
    $sudo $chown $USER:users \
    $mandir/guestbridge.1
    \builtin printf "%s\n" ${Mod[@]} >/tmp/guestbridge.conf
    $sudo $chmod u=r,go= /tmp/guestbridge.conf
    $sudo $mv -f /tmp/guestbridge.conf $moddir/guestbridge.conf
    $ln -fs $qemu_system_x86_64 /usr/local/bin/qemu
    $sudo $mkdir -p $confdir
    $sudo $chown -R $USER:kvm $confdir
    $sudo $chmod -R u=rwx,g=rx $confdir
    $sudo $mkdir -p $guestbridgedir/ovmf/
    $sudo $chown -R $USER:kvm $guestbridgedir/
    $sudo $chmod -R u=rwx,g=rx $guestbridgedir/
    $sudo $cp $ovmfdir/OVMF_CODE.fd $guestbridgedir/ovmf/OVMF_CODE.fd 
    $sudo $chown \$USER:kvm $guestbridgedir/ovmf/OVMF_CODE.fd 
    $sudo $chmod gu=r,o= $guestbridgedir/ovmf/OVMF_CODE.fd 
    $sudo $cp $ovmfdir/OVMF_VARS.fd $guestbridgedir/ovmf/OVMF_VARS.fd 
    $sudo $chown \$USER:kvm $guestbridgedir/ovmf/OVMF_VARS.fd 
    $sudo $chmod gu=r,o= $guestbridgedir/ovmf/OVMF_VARS.fd 
    $sudo $mkdir -p $socksdir 
    $sudo $chown \$USER:kvm $socksdir 
    $sudo $chmod gu=rwx,o= $socksdir 
    $sudo $mkdir -p $isodir 
    $sudo $chown \$USER:kvm $isodir 
    $sudo $chmod u=rwx,g=rx,o= $isodir 
    $sudo $mkdir -p $vbiosdir 
    $sudo $chown \$USER:kvm $vbiosdir 
    $sudo $chmod u=rwx,g=rx,o= $vbiosdir 
    [[ -x /usr/lib/qemu/virtiofsd ]] && \
    $sudo $ln -sf /usr/lib/qemu/virtiofsd $bindir/virtiofsd
}
gb.hugepages()
{
#    set -x
    local num=2200
    local tmpfile=/tmp/\${RANDOM}
    local kvm=\$($egrep -w kvm /etc/group|$cut -d: -f3)
    local entry="hugetlbfs /dev/hugepages hugetlbfs mode=1770,gid=\${kvm} 0 0"
    $cp /etc/fstab \${tmpfile}
    $egrep -q "hugepages" \${tmpfile}
    if [[ \$? == 0 ]];then
        $sed -i "s;^.*hugepages.*\$;\${entry};g" \${tmpfile}
    else
        \builtin printf "%s\n" "\$entry" >> \${tmpfile}
    fi
    $sudo $cp \${tmpfile} /etc/fstab
    $sudo $umount -f /dev/hugepages
    $sudo $mount /dev/hugepages
    \builtin echo \$num|$sudo $tee /proc/sys/vm/nr_hugepages
    \builtin echo "vm.nr_hugepages = \$num"|$sudo $tee /etc/sysctl.d/40-hugepages.conf
    set +x
}
gb.resetconfig()
{
    $sudo $rm -f $moddir/guestbridge.conf
    $sudo $rm -f $mandir/guestbridge.1 
    $sudo $rm -f $moddir/guestbridge.conf 
    $sudo $rm -f $moddir/qemu 
}
gb.mac()
{
    # unicast mac address only.
    # locally admin address.
    declare -A Base10To16=( \
    [0]="0" \
    [1]="1" \
    [2]="2" \
    [3]="3" \
    [4]="4" \
    [5]="5" \
    [6]="6" \
    [7]="7" \
    [8]="8" \
    [9]="9" \
    [10]="a" \
    [11]="b" \
    [12]="c" \
    [13]="d" \
    [14]="e" \
    [15]="f" \
    )
    local type=\$((\$RANDOM%4*4+2))
    local OUI=0
    \builtin printf "%s\n" \
    "\${Base10To16[\$((\$RANDOM%16))]}\${Base10To16[\$type]}:\
\${Base10To16[\$((\$OUI))]}\${Base10To16[\$((\$OUI))]}:\
\${Base10To16[\$((\$OUI))]}\${Base10To16[\$((\$OUI))]}:\
\${Base10To16[\$((\$RANDOM%16))]}\${Base10To16[\$((\$RANDOM%16))]}:\
\${Base10To16[\$((\$RANDOM%16))]}\${Base10To16[\$((\$RANDOM%16))]}:\
\${Base10To16[\$((\$RANDOM%16))]}\${Base10To16[\$((\$RANDOM%16))]}"
}
gb.tap.delete()
{
    local name=\${1:?[tap name e.g:tap0]}
    $ip link|$egrep -vw "\${tap}:" >/dev/null || return 0
    $sudo $ip tuntap delete dev \${name} mode tap
    $ip tap
}
gb.perm()
{
    local help='[dir][user:group][dirperm][fileperm]'
    local dir=\${1:?\$help}
    local ownership=\${2:?\$help}
    local dirperm=\${3:?\$help}
    local fileperm=\${4:?\$help}
    [[ -d \${dir} ]] || return
    [[ \$($id -u) == 0 ]] || local cmd=$sudo
    \$cmd $find \$dir -type d -exec $chown \$ownership {} \;
    \$cmd $find \$dir ! -type d -exec $chown \$ownership {} \;
    \$cmd $find \$dir -type d -exec $chmod \$dirperm {} \;
    \$cmd $find \$dir ! -type d -exec $chmod \$fileperm {} \;
}
gb.bdf()
{
    local interface=\${1:?[interface]}
    $ethtool --driver \${interface}|\
    $egrep -w "bus-info:"|\
    $sed "s;bus-info: \(.*\);\1;"
}
gb.bridge.add()
{
  local name=\${1:?[bridge name][nic]}
  local nic=\${2:?[nic]}
  $ip link |$egrep -w "\${nic}:" >/dev/null || return 1
  $ip link |$egrep -w "\${name}:" >/dev/null &&  return 0
  $sudo $ip address flush dev \${nic}  
  $sudo $ip link add name \${name} type bridge
  $sudo $ip link set \${name} up 
  $sudo $ip link set \${nic} down
  $sudo $ip link set \${nic} up
  $sudo $ip link set \${nic} master \${name}
}
SUB
)
}
gb.substitute
builtin unset -f gb.substitute

