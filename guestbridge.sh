gb.substitute()
{
    local seed confdir moddir guestbridgedir socksdir virtiofsdsocksdir vfiodir \
    blacklist bindir mandir ovmfdir cmd i cmdlist='sed shred perl dirname
    basename cat ls cut bash man mktemp egrep env mv sudo
    cp chmod ln chown rm touch head mkdir id find ss file
    qemu-img qemu-system-x86_64 modprobe lsmod socat ip flock
    lspci tee umount mount grub-mkconfig ethtool sleep modinfo
    qemu-nbd lsusb realpath mkinitcpio parted less systemctl virtiofsd'
    declare -A Devlist=(
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
        "$FUNCNAME says: ( $reslist ) These Required Commands are missing."
        return
    }
    [[ -z $devlist ]] ||\
    \builtin printf "%s\n" \
    "$FUNCNAME says: ( $devlist ) These Optional Commands for further development."

    perl_version="$($perl -e 'print $^V')"
    confdir='/srv/kvm/conf/'
    moddir='/etc/modules-load.d/'
    guestbridgedir='/srv/kvm/'
    socksdir='/srv/kvm/socks/'
    vfiodir='/dev/vfio/'
    bindir='/usr/local/bin/'
    mandir='/usr/local/man/man1'
    ovmfdir='/usr/share/edk2-ovmf/x64/'
    blacklist='/etc/modprobe.d/blacklist.conf'
    seed='${RANDOM}${RANDOM}'
    virtiofsdsocksdir='/run/virtiofsd/'
    [[ -d  $ovmfdir ]] || \builtin \printf "%s\n" "${FUNCNAME}: $ovmfdir" 
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
    vfio_mdev
    vfio_iommu_type1
    vfio_pci
    )
    \builtin \source <($cat<<-SUB

gb.virtiofsd.stop()
{
    ps.kill virtiofsd
    declare -a Pid=(\$($sudo $ls ${virtiofsdsocksdir})) 
    [[ -n \${Pid[0]} ]] || return
    $sudo $rm -rf ${virtiofsdsocksdir}
}
gb.virtiofsd.config()
{
    local guestname=\${1:?\${FUNCNAME}:[guest host name/imagefile/configfile]}
#    set -o xtrace
    guestname=\${guestname##*/}
    guestname=\${guestname%.*}
    [[ -r ${confdir}/\${guestname} ]] || { set +o xtrace; return; }
    local sharedir=\$($egrep "virtiofsd" ${confdir}/\${guestname}|$sed "s;^.*virtiofsd/GUESTNAME-\(.*\).sock.*\$;\1;")
    [[ -n \${sharedir} ]] || { set +o xtrace; return; }
    local socketname="\${guestname}-\${sharedir}.sock"
    local socketpath="${virtiofsdsocksdir}\${socketname}"
    [[ -S \${socketpath} ]] && { set +o xtrace; return; }
    sharedir=\${sharedir//@//}
    local tmpfile=/var/tmp/${seed}
    local tag=\${sharedir%/}
    tag=\${tag##*/}
    [[ -d \$sharedir ]] || { set +o xtrace; return; }
    $cat <<-VIRTIOFSDSTART > \${tmpfile}
#!$env $bash
    \builtin exec $virtiofsd --syslog \
    --socket-path="\${socketpath}" \
    --thread-pool-size=6 \
    -o source=\${sharedir} &
VIRTIOFSDSTART
    $chmod u=rwx \${tmpfile}
    $sudo \${tmpfile}
    $rm -f \${tmpfile}
    $sleep 4
    gb.perm ${virtiofsdsocksdir} root:kvm g=rwx g=rw
    set +o xtrace
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
        file="/sys/bus/pci/drivers/\${Entry[2]}/0000:\${Entry[0]}/boot_vga"
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
_gb.swapgpu()
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
#say Dumper(\\@_);
GBSWAPGPU
))
#    set -o xtrace
    local i file driver device module
    for i in \${Res[@]};do
#        echo \$i
        device=\${i%%@*}
        i=\${i#*@}
        driver=\${i%@*}
        module=\${i#*@}
        file="/sys/bus/pci/drivers/\${module}/0000:\${device}/boot_vga"
        # Swap off
        if [[ -r \${file} && "\$($cat \$file)" == 1 ]];then
            if [[ \${driver} =~ 'none' ]];then
                gb.bind \${device} vfio-pci
                continue
            fi
            gb.rebind \${device} \${driver} vfio-pci
            [[ \${driver} =~ \${module} ]] && gb.unloadmod \${module}
            continue
        fi
        # Swap on 
        gb.loadmod \${module} 
        if [[ \${driver} =~ 'none' ]];then
            gb.bind \${device} \${module}
            continue
        fi
#        [[ \${driver} =~ \${module} ]] && continue
        gb.rebind \${device} \${driver} \${module}
    done
    set +o xtrace
}
gb.imageinstall()
{
    local image=\${1:?[qcow2 image file]}
    local name=\${image##*/}
    name=\${name%.*}
    local mp=/var/tmp/\${name}
    local config=$confdir/\${name}
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
        $rm -f ${virtiofsdsocksdir}/${virtiofsdsocksdir////.}\${guestname}-*
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
    local mp=\${1:?[mount point]}
    mp=\$($realpath \$mp)
    $sudo umount -f \$mp
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
    local help="\${FUNCNAME}:[guest image file][opt: bridge name][opt: nic][optional debug flag:1|0]"
    gb.virtiofsd.config \${@:?\${help}} 
    gb.lock _gb.run \${@:?\${help}}
}
_gb.run()
{
    local guestimg=\${1}
    local guestname=\${guestimg##*/}
    guestname=\${guestname%.*}
    local guestcfg=${confdir}/\${guestname}
    local bridge=\${2:-.}
    local nic=\${3:-.}
    local debug=\${4}
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
    $id|$egrep -w kvm >/dev/null || return
    [[ -f \${guestcfg} ]] || return
    [[ -a \${guestimg} ]] || return
    [[ -c $vfiodir/vfio ]] || return
    [[ -S ${socksdir}/\${guestname} ]] && return
    local tmpfile=/var/tmp/\${RANDOM}
    declare -a Config=(\$($sed -e "s;^#.*\$;;g" \
    -e "s;GUESTNAME;\${guestname};g" \
    -e "s;MAC;\$(gb.mac);g" \
    -e "s;PORT;\$((\${RANDOM}%100+9000));" \
    -e "s;GUESTIMG;\${guestimg};" \${guestcfg})) 

    if [[ \${#bridge} -gt 1 && \${#nic} -gt 1 ]];then
        $egrep -q -m 1 "tap,"  <<<\${Config[@]} && gb.tap bridge nic guestname
    fi
    gb.rebind2config \${guestcfg} 
    gb.perm /dev/vfio root:kvm g=rwx g=rw
    $cat<<KVMGUEST> \${tmpfile}
#!$env $bash
    \builtin exec $qemu_system_x86_64 -chroot /var/tmp/ -runas kvm \${Config[@]} && $touch /tmp/111 &
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
    gb.bridge.add "\${!1}" "\${!2}" || return
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
#    set -o xtrace
    [[ -S ${socksdir}/\$name ]] && {
        $socat - UNIX-CONNECT:${socksdir}/\$name <<<"\${cmd}"
        set +o xtrace
        return
    }
    [[ -S \$name ]] && $socat - UNIX-CONNECT:\$name  <<<"\${cmd}"
    set +o xtrace
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

   
    # verify binded vfio-pci devices
    dmesg | egrep -i vfio_pci
    output: vfio_pci: add [9809:1301]
    lspci -vmk  
    Driver: vfio-pci

    # Find out BDF of the Nic for pass through
    gb.iommu |egrep "Intel Corporation 82579"
    output BDF : 00:18.0 Ethernet controller 
    # configure and install guest config file
    gb.vmreconfig vm/guestname

    # Start guest vm
    gb.run [guestname] br0 enp0s1

    # Interact with QEMU monitor
    gb.socks [guestname] help
    gb.socks [guestname] [info name|system_powerdown|quit]
    # Shutdown guest and rebind devices passed through
    gb.shutdown [guestname]

    # If guest don't boot direct into OS but stay on UEFI shell
    # grub.reconfig inside guest OS.

    # install systemd cron service.
    # enable auto release devices passed through to guest.
    gb.fun2script
    gb.croninstall
    gb.enable
    gb.start
    gb.timer

    # Mount/Unmount Modify qcow2
    gb.mount.qcow2
    # Mount partitions and chroot into it.

    # Leave qemu monitor inside telnet
       ^]
       telnet> quit
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
    [[ \$($id -u) == 0 ]] || local cmd=$sudo
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
gb.create.img()
{
    local name=\${1:?[name][size][format: raw/qcow2 def:qcow2]}
    local size=\${2:?[size]}
    local format=\${3:-qcow2}
    [[ ! -d $guestbridgedir ]] && $sudo $mkdir -p $guestbridgedir
    $qemu_img create -f \${format} $guestbridgedir/\${name}.\${format} \${size}
    $sudo $chown \$USER:kvm $guestbridgedir/\${name}.\${format}
    $sudo $chmod ug=rw $guestbridgedir/\${name}.\${format}
    $qemu_img info $guestbridgedir/\${name}.\${format}
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
}
gb.hugepages()
{
#    set -o xtrace
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
    \builtin echo 5500|$sudo $tee /proc/sys/vm/nr_hugepages
    \builtin echo "vm.nr_hugepages = 5500"|$sudo $tee /etc/sysctl.d/40-hugepages.conf
    set +o xtrace
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
gb.unbind()
{
    local help='[bdf][unbind driver: ehci-pci/vfio-pci]'
    local bdf=\${1:?\$help}
    local unbind=\${2:?\$help}
    bdf="0000:\${bdf}"
    [[ \$($id -u) == 0 ]] || local cmd=$sudo
#    set -o xtrace
    [[ -d "/sys/bus/pci/drivers/\${unbind}/" ]] || unbind=\${unbind/_/-}
    local unbindpath="/sys/bus/pci/drivers/\${unbind}/unbind"
    \builtin echo \${bdf} |\$cmd $tee \${unbindpath} 2>/dev/null
    $lspci -k -s \${bdf}
 #   set +o xtrace
}
gb.rebind()
{
    local help='[bdf][unbind driver: ehci-pci/vfio-pci][bind driver: ehci-pci/vfio-pci]'
    local bdf=\${1:?\$help}
    local unbind=\${2:?\$help}
    local bind=\${3:?\$help}
    bdf="0000:\${bdf}"
    [[ \$($id -u) == 0 ]] || local cmd=$sudo
#    set -o xtrace
    [[ -d "/sys/bus/pci/drivers/\${unbind}/" ]] || unbind=\${unbind/_/-}
    [[ -d "/sys/bus/pci/drivers/\${bind}/" ]] || bind=\${bind/_/-}
    local idpath="/sys/bus/pci/drivers/\${bind}/new_id"
    local unbindpath="/sys/bus/pci/drivers/\${unbind}/unbind"
    local bindpath="/sys/bus/pci/drivers/\${bind}/bind"
    local id=\$($lspci -s \${bdf} -n |$cut -d' ' -f3)
    \builtin echo \${bdf} |\$cmd $tee \${unbindpath} 2>/dev/null
    \builtin echo "\${id/:/ }" |\$cmd $tee \${idpath} 2>/dev/null
    \builtin echo "\${bdf}" |\$cmd $tee \${bindpath} 2>/dev/null
    $lspci -s \${bdf} -k
 #   set +o xtrace
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
gb.bind()
{
    local help='[bdf][bind driver: ehci-pci/vfio-pci]'
    local bdf=\${1:?\$help}
    local bind=\${2:?\$help}
    bdf="0000:\${bdf}"
    [[ \$($id -u) == 0 ]] || local cmd=$sudo
    [[ -d "/sys/bus/pci/drivers/\${bind}/" ]] || bind=\${bind/_/-}
    local idpath="/sys/bus/pci/drivers/\${bind}/new_id"
    local bindpath="/sys/bus/pci/drivers/\${bind}/bind"
    local id=\$($lspci -s \${bdf} -n |$cut -d' ' -f3)
    \builtin echo "\${id/:/ }" |\$cmd $tee \${idpath} 2>/dev/null
    \builtin echo "\${bdf}" |\$cmd $tee \${bindpath} 2>/dev/null
    $lspci -s \${bdf} -k
}
SUB
)
}
gb.substitute
builtin unset -f gb.substitute
