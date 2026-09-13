guestbridge.substitute()
{
    local cmdlist reslist devlist pkglist cmd i pkg
    cmdlist=(dirname basename cat mv sudo cp chmod ln chown rm touch realpath
    head mkdir perl mktemp shred grep sed tee id file cut python flock groups
    lspci find ethtool tail sleep ip swtpm systemctl systemd-delta less lsmod modprobe
    ps socat qemu-system-x86_64 qemu-img zgrep lsmod qemu-nbd umount
    screen groupadd useradd passwd gpasswd mkinitcpio dd dmesg rsync)

    for cmd in ${cmdlist[@]};do
        i=($(\builtin type -afp $cmd))
        [[ -n $i ]] || {
            \builtin printf "%s\n" "$FUNCNAME Require: $cmd"
#            return
        }
        local ${cmd//-/_}=${i:-:}
    done

    pkglist=(python-pytz python-termcolor qemu-base)
    for pkg in ${pkglist[@]};do
        pacman -Qi $pkg >/dev/null 2>&1 && continue
        \builtin printf "%s\n" "$FUNCNAME Require pkg: $pkg"
#        return
    done

    devlist=(pylint dot pyreverse)
    for cmd in ${devlist[@]};do
        i=($(\builtin type -afp $cmd))
        [[ -n $i ]] || {
            \builtin printf "%s\n" "$FUNCNAME Optional: $cmd"
            continue
        }
        local ${cmd//-/_}=${i:-:}
    done

    local perl_version="$($perl -e 'print $^V')"
    local python_bin="$($realpath $python)"
    local python_version="$($basename ${python_bin})"
    local python_sitedir="/usr/lib/${python_version}/site-packages"
    local vendor_perl=/usr/share/perl5/vendor_perl/
    local libdir=/usr/local/lib
    local python_libdir="$libdir/python/"
    local includedir=/usr/local/include/
    local bindir=/usr/local/bin/
    local seed='${SRANDOM}'
    local signal='HUP INT TERM EXIT'
    local guesthomedir='/srv/kvm/'
    local ovmfdir='/usr/share/edk2/x64/'
    local sec_ovmfdir='/usr/share/edk2-ovmf-fedora/OVMF/'
    local moddir='/etc/modules-load.d/'
    local mandir='/usr/local/man/man1'
    [[ -d  $ovmfdir ]] ||\
    \builtin \printf "%s\n" "${FUNCNAME}: Requre: $ovmfdir"
    [[ -d  $ovmfdir ]] ||\
    \builtin \printf "%s\n" "${FUNCNAME}: optional: $sec_ovmfdir"
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
    mdev
    vfio_iommu_type1
    vfio_pci
    )

    \builtin source <($cat<<-SUB
gb.socat.serial()
{
    : VM prerequest GRUB_CMDLINE_LINUX="console=tty0 console=ttyS0,115200n8"
    : systemctl enable serial-getty@ttyS0.service
    : systemctl enable serial-getty@ttyS1.service
    : systemctl start serial-getty@ttyS0.service serial-getty@ttyS1.service

    local help='[vmXY] [serial number 0 | 1]'
    local group=\${1:?\$help}
    local number=\${2:?\$help}
    local -A Invert=([1]=0 [0]=1)
    local sockspath=$guesthomedir/\${group}/socks/serial\${number}
    \builtin test -n "\${Invert[\$number]}" || {
        \builtin echo "invalid Serial number: \$number" >&2
        set +x
        return 1
    }
    \builtin test -S \$sockspath || {
        \builtin echo "invalid \$sockspath" >&2
        set +x
        return 1
    }
    $ps auxww | $grep "[s]ocat.*serial\${number}" >/dev/null && {
        \builtin echo " \$group \$number already taken. Try \$group \${Invert[\$number]}" >&2
        set +x
        return 1
    }
    $socat -,raw,echo=0,escape=0x03,icanon=0,isig=1,nonblock UNIX-CONNECT:/\$sockspath
}
gb.copy()
{
    local help='[source image file] [target image: qcow2]'
    local source=\${1:?\$help}
    local target=\${2:?\$help}
    $qemu_img dd -f raw -O qcow2 if=\${source} of=\${target} bs=4M
}
gb.lspci.tree()
{
    $lspci -tv | $less
}
gb.usb.unbind()
{
    local hostport=\${1:?[ bus-port.device: 1-1.2]}
    \builtin echo "\$hostport" | $sudo $tee /sys/bus/usb/drivers/usb/unbind
}
gb.usb.rebind()
{
    local hostport=\${1:?[ bus-port.device: 1-1.2]}
    \builtin echo "\$hostport" | $sudo $tee /sys/bus/usb/drivers/usb/bind
}
gb.backup()
{
    \builtin echo "gb.pause -> gb.backup -> gb.resume"
    local help='[vm dir] [backup dir]'
    local vmdir=\${1:?\$help}
    local backupdir=\${2:?\$help}
    $sudo $rsync -av --partial --progress \$vmdir \$backupdir
}
gb.convert.qcow2raw()
{
    local help='[qcow2 file] [raw file]'
    local infile=\${1:?\$help}
    local outfile=\${2:?\$help}
    $sudo $qemu_img convert -f qcow2 -O raw \$infile \$outfile
}
gb.convert.2qcow2()
{
    local help='[iso/raw] [qcow2 file]'
    local infile=\${1:?\$help}
    local outfile=\${2:?\$help}
    $sudo $qemu_img convert -f raw -O qcow2 \$infile \$outfile
}
gb.cmd.bind()
{
    local help='[amdgpu] [bdf 0c:00.0]'
    local driver=\${1:?\$help}
    local bdf=\${2:?\$help}
    bdf="0000:\$bdf"
    [[ -a "/sys/bus/pci/drivers/\$driver/new_id" ]] || return 1
    \builtin echo \$bdf | $sudo $tee /sys/bus/pci/drivers/\$driver/new_id
}
gb.resizebar()
{
    local help='[3|0] [bdf 0c:00.0]'
    local value=\${1:?\$help}
    local bdf=\${1:?\$help]}
    bdf="0000:\$bdf"
    local bar="/sys/bus/pci/devices/\$bdf/resource2_resize"
    [[ -a "\$bar" ]] || return 1
    \builtin echo \$value | $sudo $tee "\$bar"
}
gb.diagram()
{
    local name infile outfile
    local help='[project dir]'
    local projectdir=\${1:?\$help}
    projectdir="\$($realpath \$projectdir)"
    local projectname="\$($basename \$projectdir)"
#    set -x
    if [[ ! -d \$projectdir || ! -d \${projectdir}/src || ! -d \${projectdir}/dist ]];then
        \builtin echo "invalid \$project"
        return 1
    fi
    $pyreverse --all-associated --all-ancestors --output-directory \${projectdir}/dist --project \$projectname \${projectdir}/src
    for infile in \${projectdir}/dist/*.dot;do
        name=\${infile##*/}
        name="\${projectdir}/dist/\${name/.dot/}.addon"
        $sed -i "s;src;gb;g" \$infile
        $sed -i "s;^};;" \$infile
        $cat \$name >> \$infile
        \builtin echo "}" >> \$infile
        outfile=\${infile%.dot}.png
        $dot -Tpng \$infile -o \$outfile
    done
    $chmod o=r \${projectdir}/dist/*.png
    $cp -av \${projectdir}/dist/*.png /tmp/
    set +x
}
gb.vlan.reconfig()
{
    local conf=\${1:?[vm/GUESTNAME/vlan.conf]}
    $sudo $cp \$conf $guesthomedir/
    $sudo $chown kvm:kvm $guesthomedir/vlan.conf
    $sudo $chmod gu=r,o= $guesthomedir/vlan.conf
}
gb.pci.reconfig()
{
    local conf=\${1:?[vm/GUESTNAME/pci.conf]}
    $sudo $cp \$conf $guesthomedir/
    $sudo $chown kvm:kvm $guesthomedir/pci.conf
    $sudo $chmod gu=r,o= $guesthomedir/pci.conf
}
gb.id2bdf()
{
    local help='[macaddress | device id]'
    local input=\${1:?\$help}
    local mac pattern1='[[:alnum:]][[:alnum:]]\:[[:alnum:]][[:alnum:]]\:[[:alnum:]][[:alnum:]]\:[[:alnum:]][[:alnum:]]\:[[:alnum:]][[:alnum:]]\:[[:alnum:]][[:alnum:]]'
    local id pattern2='[[:digit:]][[:digit:]][[:digit:]][[:digit:]]\:[[:digit:]][[:digit:]][[:digit:]][[:digit:]]'
#    set -x
    if [[ "\$input" == \$pattern1 ]];then
        mac=\$input
    fi
    if [[ "\$input" == \$pattern3 ]];then
        \builtin echo "device id"
    fi
    set +x
}
gb.vbios()
{
    $cat<<-GBVBIOS
    First Gpu boot on windows
    techpowerup GPU-Z dump the Secound GPU bios
GBVBIOS
}
gb.vbios.dummy()
{
    local destdir=\${1:?[dest dir]}
    $dd if=/dev/zero of=\$destdir/dummy.rom bs=1M count=1
}
gb.img.convert()
{
    \builtin echo "/dev/sdX Requires double the Size of qcow2 file."
    local help='[infile qcow2] [/dev/sdX]'
    local infile=\${1:?\$help}
    local dev=\${2:?\$help}
    $sudo $qemu_img dd -f qcow2 -0 raw bs=4M if=\${infile} of=\${dev}
}
gb.mkinitcpio()
{
    local conf=\${1:?[mkinitcpio.conf]}
    $sudo $cp \$conf /etc/mkinitcpio.conf 
    $sudo $chmod u=rw,go=r /etc/mkinitcpio.conf
    $sudo $mkinitcpio && $sudo $mkinitcpio -g /boot/initramfs-linux.img
}
gb.hugepages()
{
#    set -x
    local num=2200
    local tmpfile=/tmp/\${RANDOM}
    local kvm=\$($grep -E -w kvm /etc/group|$cut -d: -f3)
    local entry="hugetlbfs /dev/hugepages hugetlbfs mode=1770,gid=\${kvm} 0 0"
    $cp /etc/fstab \${tmpfile}
    $grep -E -q "hugepages" \${tmpfile}
    if [[ \$? == 0 ]];then
        $sed -i "s;^.*hugepages.*\$;\${entry};g" \${tmpfile}
    else
        \builtin printf "%s\n" "\$entry" >> \${tmpfile}
    fi
    $sudo $mv \${tmpfile} /etc/fstab
    $sudo $umount -f /dev/hugepages
    $sudo $mount /dev/hugepages
    \builtin echo \$num|$sudo $tee /proc/sys/vm/nr_hugepages
    \builtin echo "vm.nr_hugepages = \$num"|$sudo $tee /etc/sysctl.d/40-hugepages.conf
    $sudo $chmod go=r /etc/sysctl.d/40-hugepages.conf
    set +x
}
gb.add.group.random-gid()
{
    local help='[group name]'
    local group=\${1:?\$help}
    local commonid="\$((\$RANDOM\$RANDOM % 50000 + 10000))"
    $sudo $groupadd --force \${group} -g \${commonid}
}
gb.add.group.system()
{
    : Add KVM system user and group
    : Add current user in this group
    local user=\$USER
    local kvm_user=\${1:-kvm}
    local kvm_group=\${2:-kvm}
    local homedir=/dev/shm/
    $sudo $groupadd --system \${kvm_user}
    $sudo $useradd --system --home-dir \$homedir -g \$kvm_group -s /bin/nologin \$kvm_user
    $sudo $passwd --lock \$kvm_user
    gb.add.user2group \$kvm_user \$kvm_group
    \builtin echo "Logout and Login Again."
}
gb.add.user2group()
{
    local help='[user] [group]'
    local user=\${1:?\$help}
    local group=\${2:?\$help}
    $sudo $gpasswd -a \$user \$group
}
gb.uninstall.start.cron()
{
    $sudo $rm -f /lib/systemd/system/gb.start.service
    $sudo $rm -f $bindir/gb.start
    $sudo $rm -f /srv/kvm/gb.conf
    $sudo $systemctl daemon-reload
}
gb.vm.reconfig()
{
    local help='[vm config file] [vm image file]'
    local config=\${1:?\$help}
    local image=\${2:?\$help}
    local name=\${config##*/}
    local format=\${image##*.}
    local tmpfile=/dev/shm/${seed}
    local group=\$(dirname \$image)
    group=\$($basename \$group)
    local conffile=${guesthomedir}\${group}/conf/\$name
    $file -b \$config | $grep -q "text" || {
        \builtin echo "invalid \$config"
        return 1
    } 
    $grep -E '^vm' /etc/group >/dev/null || {
       \builtin echo "invalid \$group"
        return 1
    }
    $sed -e "s;^#.*\$;;g" -e "/^\$/d" \
    -e "s;GUESTNAME;\$name;g" \
    -e "s;USER;kvm;g" \
    -e "s;GROUP;\$group;g" \
    -e "s;GUESTIMG;\$image;g" \
    -e "s;FORMAT;\$format;g" \
    \$config > \$tmpfile
    $sudo $mv -f \$tmpfile \$conffile
    $sudo $chown -f kvm:\$group \$conffile 
    $sudo $chmod -f ug=r,o= \$conffile
}
gb.grub.reconfig()
{
    local help='[vm/NAME/grub] [efi dir def: /efi]'
    local conf=\${1:?[vm/NAME/grub]}
    local efidir=\${2:-/efi}
    $sudo $cp \${conf} /etc/default/grub
    # UEFI BOOT
    $grep -E -q -w "/dev/.* \$efidir" /proc/mounts || {
        \builtin echo "invalid \$efidir"
        return 1
    }
    $sudo $grub_install --target=x86_64-efi --efi-directory=\$efidir \
    --bootloader-id=grub-efi --recheck && \
    $sudo $grub_mkconfig -o /boot/grub/grub.cfg
    $sudo $chmod go=r /boot/grub/grub.cfg
}
gb.prerequest()
{
    : Verify if prerequest fullfilled.
    {
    $grep -w -m 1 -o -e "vmx" -e "svm" /proc/cpuinfo || {
        \builtin echo "vmx/svm not enabled in BIOS"
        return 1
    }
    \builtin printf "%s\n\n" "BIOS settings enabled."

    $sudo $dmesg | $grep "BAR=" || {
        \builtin printf "%s\n\n" "Optional Resize BAR Disabled."
    }
    $zgrep -e CONFIG_KVM -e VIRTIO /proc/config.gz
    $lsmod | $grep -e kvm -e virtio
    } | $less
}
gb.bdf()
{
    ${bindir}/guestbridge find_bdf_by_interface \${@}
}
gb.modprobeconfig()
{
    local dir=\${1:?[vm directry path contains vfio.conf and mkinitcpio.conf]}
    if [[ ! -d \$dir ]];then
        \builtin echo "should be a vm directry, NOT a file"
        return 1
    fi
    if [[ -r \$dir/vfio.conf ]];then
        $sudo $cp \$dir/vfio.conf /etc/modprobe.d/vfio.conf
        $sudo $chmod u=rw,go=r /etc/modprobe.d/vfio.conf
    fi
    [[ -r \$dir/mkinitcpio.conf ]] &&\
    gb.mkinitcpio \$dir/mkinitcpio.conf
}
gb.lspci()
{
    $lspci -nnvmmk | $less
}
gb.start()
{
    : Prerequist COPY vm/GUESTNAME/conf ${guesthomedir}/gb.conf
    : /etc/sudoers kvm LOCALHOST= NOPASSWD: ${bindir}/guestbridge
    local i prefix suffix img backup start
    local backupconf=${guesthomedir}/gb.conf
    [[ -r "\${backupconf}" ]] || {
       \builtin echo "invalid \${backupconf}"
        return 1
    }
    set -x
    declare -a Conf=(\$(<\$backupconf))
    for i in \${Conf[@]};do
        \builtin read img backup start <<<"\${i//:/ }"
        [[ \$start == 'start' ]] || continue
        $sleep 10
        prefix=\${img%-*}
        suffix=\${img#*-}
        ${bindir}/guestbridge prestartvm \${prefix}-\${suffix}
    done
    set +x
}
gb.uninstall.start.cron()
{
    $sudo $rm -f /lib/systemd/system/gb.start.service
    $sudo $rm -f $bindir/gb.start
    $sudo $rm -f /srv/kvm/gb.conf
    $sudo $systemctl daemon-reload
}
gb.limits()
{
    : Require Logout and Login again
    : To support Non-root pci passthrough by allowing  Admin="\$USER" user lock memory limits.
    : And Systemd LimitMEMLOCK
    : man systemd.exec
    local config=\${1:?[vm/HOSTNAME/limits.conf]}
    local tmpfile=/dev/shm/$seed
    $sudo $cp \${config} /etc/security/limits.conf
    $sudo $mkdir -p /etc/systemd/system/gb.start.service.d/
    $sudo $chmod a=rx /etc/systemd/system/gb.start.service.d/
    $cat >\$tmpfile <<-BGSTARTLIMIT
[Service]
LimitMEMLOCK=32000000
BGSTARTLIMIT
    $sudo $mv \$tmpfile /etc/systemd/system/gb.start.service.d/limit.conf
    $sudo $chown root:adm /etc/systemd/system/gb.start.service.d/limit.conf
    $sudo $chmod ug=r /etc/systemd/system/gb.start.service.d/limit.conf
    $sudo $systemctl daemon-reload
    $sudo $systemd_delta
    $systemctl show gb.start | $grep LimitMEMLOCK
    \builtin echo "Logout and Login Again."
}
gb.install.start.cron()
{
    local conf=\${1:?[vm/GUESTNAME/gb.conf]}
    gb.uninstall.start.cron
    bash.fun2script gb.start kvm:kvm gu=rx,o=
    $sudo $cp \$conf /srv/kvm/gb.conf
    $sudo $chown kvm:kvm /srv/kvm/gb.conf
    $sudo $chmod gu=r,o= /srv/kvm/gb.conf
    $sudo $cp conf/gb.start.service /lib/systemd/system/gb.start.service
    $sudo $chmod 0644 /lib/systemd/system/gb.start.service
    $sudo $systemctl daemon-reload
}
gb.bind()
{
    $bindir/guestbridge prebind "\$@"
}
gb.rebind()
{
    $bindir/guestbridge prerebind "\$@"
}
gb.unbind()
{
    $bindir/guestbridge preunbind "\$@"
}
gb.snapshot.restore()
{
    $bindir/guestbridge snapshotrestore "\$@"
}
gb.snapshot.delete()
{
    $bindir/guestbridge snapshotdelete "\$@"
}
gb.uninstall.removesocks.cron()
{
    $sudo $rm -f /lib/systemd/system/gb.removesocks.service
    $sudo $rm -f /lib/systemd/system/gb.removesocks.timer
    $sudo $rm -f /lib/systemd/system/timers.target.wants/gb.removesocks.timer
    $sudo $rm -f $bindir/gb.remove.allsocks
    $sudo $systemctl daemon-reload
}
gb.install.removesocks.cron()
{
    : Prerequest add kvm to vmXY group
    $sudo $cp conf/gb.removesocks.service /lib/systemd/system/gb.removesocks.service
    $sudo $cp conf/gb.removesocks.timer /lib/systemd/system/gb.removesocks.timer
    $sudo $chmod u=rw,go=r /lib/systemd/system/gb.removesocks.service
    $sudo $chmod u=rw,go=r /lib/systemd/system/gb.removesocks.timer
    $sudo $ln -sf /lib/systemd/system/gb.removesocks.timer \
    /lib/systemd/system/timers.target.wants/gb.removesocks.timer
    $sudo $systemctl daemon-reload
}
gb.remove.allsocks()
{
#    set -x
    $bindir/guestbridge removeallsocks
    $bindir/guestbridge brief
    set +x
}
gb.snapshot()
{
    $bindir/guestbridge snapshot "\$@"
}
gb.snapshot.repo()
{
    $bindir/guestbridge snapshotrepo
}
gb.img.info()
{
    $bindir/guestbridge imageinfo "\$@"
}
gb.iommu()
{
    $bindir/guestbridge iommu
}
gb.remove.socks()
{
    $bindir/guestbridge removesocks \$@
}
gb.quit()
{
    $bindir/guestbridge quit \$@
}
gb.shutdown()
{
    $bindir/guestbridge shutdown \$@
}
gb.pause()
{
    $bindir/guestbridge pause \$@
}
gb.resume()
{
    $bindir/guestbridge resume \$@
}
gb.brief()
{
    $bindir/guestbridge brief
}
gb.lint()
{
    $mv src/__init__.py /var/tmp/
    $pylint --disable multiple-statements,wrong-import-position,consider-using-with \
    -d missing-module-docstring,too-few-public-methods,protected-access,no-member \
    -d multiple-imports,missing-class-docstring,missing-function-docstring,too-many-arguments \
    -d too-many-function-args,attribute-defined-outside-init,too-many-instance-attributes src/
    $mv /var/tmp/__init__.py src/
}
gb.py.install()
{
    local name debugging=\${1:-1}
    $sudo $rm -rf $python_libdir/guestbridge
    $sudo $mkdir -p $python_libdir/guestbridge
    for i in src/*;do
        name=\${i#*/}
        $sed "0,/self.debugging = 0/s//self.debugging = \$debugging/" \$i > /tmp/\$name
        $sudo $mv -f /tmp/\$name $python_libdir/guestbridge/\$name
    done
    $sudo $chown -R root:adm $python_libdir/guestbridge
    $sudo $chmod ug=rx,o=rx $python_libdir/guestbridge
    $sudo $chmod ug=r,o=r $python_libdir/guestbridge/*
    $sed "s;DEBUGGING;\$debugging;" src/guestbridge.py > /tmp/guestbridge.py
    $sudo $mv -f /tmp/guestbridge.py $bindir/guestbridge
    $sudo $chown root:adm $bindir/guestbridge
    $sudo $chmod a=rx $bindir/guestbridge
}
gb.iommu()
{
    $bindir/guestbridge iommu |$less
}
gb.run()
{
    ${bindir}/guestbridge prestartvm "\$@"
}
gb.verify()
{
    gb.py.install 0
    $bindir/guestbridge >/dev/null
    $bindir/guestbridge iommu | $grep iommu >/dev/null || {
        builtin echo "failed 1"
        return 1
    }
    $bindir/guestbridge bdf enp2s0 | $grep 02:00.0 || {
        builtin echo "failed 2"
        return 1
    }
    $bindir/guestbridge prerebind 02:00.0 igc vfio-pci || {
        builtin echo "failed 3"
        return 1
    }
    $sleep 1
    $lspci -vmk | $grep 02:00.0 -A8 |$tail -1 | $grep vfio-pci || {
        builtin echo "failed 3"
        return 1
    }
    $bindir/guestbridge prerebind 02:00.0 vfio-pci igc || {
        builtin echo "failed 4"
        return 1
    }
    $sleep 1
    $lspci -vmk | $grep 02:00.0 -A8 |$tail -1 | $grep igc || {
        builtin echo "failed 4"
        return 1
    }
    $bindir/guestbridge bridgetap target/owl || {
        builtin echo "failed 5"
        return 1
    }
    $sleep 1
    $ip tuntap | $grep tap_vm30 || {
        builtin echo "failed 5"
        return 1
    }
    $bindir/guestbridge unbridgetap target/owl || {
        builtin echo "failed 6"
        return 1
    }
    $sleep 1
    $ip tuntap | $grep tap_vm30 && {
        builtin echo "failed 6"
        return 1
    }
    $bindir/guestbridge binding target/owl || {
        builtin echo "failed 7"
        return 1
    }
    $sleep 1
    $lspci -vmk | $grep 05:00.0 -A8 |$tail -1 | $grep vfio-pci || {
        builtin echo "failed 7"
        return 1
    }
    $bindir/guestbridge rebinding target/owl || {
        builtin echo "failed 8"
        return 1
    }
    $sleep 1
    $lspci -vmk | $grep 05:00.0 -A8 |$tail -1 | $grep igc || {
        builtin echo "failed 8"
        return 1
    }
    $bindir/guestbridge status target/owl | $grep "clean up\|shutdown\|running" || {
        builtin echo "failed 9"
        return 1
    }
    $bindir/guestbridge brief | $grep "clean up\|shutdown\|running" || {
        builtin echo "failed 10"
        return 1
    }
    builtin echo "all pass"
    set +x
}
gb.readme()
{
    [[ \$PWD =~ guestbridge ]] || return
    gb.info > README.md
}
gb.info()
{
    $less<<-KVMINFO
    ## guestbridge:
    Guest Bridge is a Kernel Virtual Machine Configuration script, written in Bash and Python.
    Supporting GPU, Mouse, Keyboard, USB, Network pass through via vfio-pci to guest OS, and automatic starting VM.
    Meanwhile the host OS remain headless. Communication with guests via Qemu QMP and SSH.
    Administrator can therefore maintain a minimal footprint on host OS and keep it secure.

    * Bios settings enable svm, iommu, Resize-bar and 4G decoding.
    gb.loadmodall
    gb.reconfig
    gb.prerequest
    gb.add.group.system
    * Add kvm to vmXY group
    gb.add.user2group
    gb.newvm
    gb.py.install
    
    * -- optional ---
    gb.hugepages
    * ---------------
    gb.limit
    gb.grub.reconfig

    * show pci device id
    gb.lspci

    * Bind vfio-pci to pci device as kernel module.
    * Load module precedence.
    gb.modprobconfig

    * Restart Host Computer
    * Verify IOMMU been enabled.
    gb.iommu

    * Find out BDF of the Nic for pass through
    gb.bdf

    * Configure and install guest config file
    gb.vm.reconfig
   
    * Configure pci device mapping
    gb.pci.reconfig

    * Configure tap vlan
    gb.vlan.reconfig
    * Start guest vm
    gb.run

    * Show help from the main program
    guestbridge

    * If guest don't boot direct into OS but stay on UEFI shell
    grub.reconfig inside guest OS.

    * Install systemd cron service.
    gb.install.start.cron
    gb.install.removesocks.cron

    * Maintenance
    * Mount/Unmount Modify qcow2
    gb.mount.qcow2
    gb.unmount.qcow2

    * Resize filesystem and partition
    gb.resize 
KVMINFO
}
gb.resize()
{
    $cat<<BGRESIZE
    # Resize filesystem and partition
    # shutdown VM
    qemu-img resize -f qcow2 disk.qcow2 500G
    qemu-img info disk.qcow2
    # Add this line to other vm conf file
    -drive file=/srv/kvm/vmNY/vm.qcow2,format=qcow2,index=1
    # boot other VM with vm.qcow2
    sudo parted /dev/sda print
    sudo parted /dev/sda
    > resizepart N 500G
    # Check partition
    sudo e2fsck -f /dev/sdaN
    sudo resize2fs /dev/sdaN
BGRESIZE
}
gb.loadmodall()
{
    $sudo $modprobe --verbose --all ${Mod[@]}
    $lsmod|$grep -E "virtio|vhost"
}
gb.loadmod()
{
    local mod=\${1:?[module to load]}
    [[ \${UID} == 0 ]] || local cmd=$sudo
    \$cmd $modprobe \$mod
}
gb.resetconfig()
{
    $sudo $rm -f $moddir/guestbridge.conf
    $sudo $rm -f $mandir/guestbridge.1
    $sudo $rm -f $moddir/guestbridge.conf
    $sudo $rm -f $moddir/qemu
}
gb.reconfig()
{ 
    [[ \$($basename \${PWD}) == guestbridge ]] || return
    gb.resetconfig
    $sudo $mkdir -p $mandir
    $sudo $chmod 0755 $mandir
    \builtin printf "%s\n" ${Mod[@]} >/tmp/guestbridge.conf
    $sudo $chmod u=r,go= /tmp/guestbridge.conf
    $sudo $mv -f /tmp/guestbridge.conf $moddir/guestbridge.conf
    $sudo $ln -sf /usr/lib/qemu/virtiofsd $bindir/virtiofsd
    $sudo $chown root:root $qemu_system_x86_64
    $sudo $ln -fs $qemu_system_x86_64 /usr/local/bin/qemu
}
gb.remove.config()
{
    $sudo $rm -f $moddir/guestbridge.conf
    $sudo $rm -f $moddir/guestbridge.conf 
    $sudo $rm -f $moddir/qemu 
}
gb.ovmf.secboot.update()
{
    local destdir=\${1:?[/srv/kvm/vmX/]}
    local grpname="\$($basename \${destdir})"
    $sudo $cp $ovmfdir/OVMF_CODE.secboot.fd \${destdir}/ovmf/\${grpname}_OVMF_CODE.secboot.fd
    $sudo $cp $ovmfdir/OVMF_VARS.secboot.fd \${destdir}/ovmf/\${grpname}_OVMF_VARS.secboot.fd
    gb.fileperm \${destdir}/ovmf/ kvm:\$grpname gu=r
}
gb.ovmf.update()
{
    local destdir=\${1:?[/srv/kvm/vmX/]}
    local grpname="\$($basename \${destdir})"
    $sudo $cp $ovmfdir/OVMF_CODE.4m.fd \${destdir}/ovmf/OVMF_CODE.fd
    $sudo $cp $ovmfdir/OVMF_VARS.4m.fd \${destdir}/ovmf/OVMF_VARS.fd
    $sudo $cp $ovmfdir/OVMF_VARS.4m.fd \${destdir}/ovmf/\${grpname}_OVMF_VARS.fd
    gb.fileperm \${destdir}/ovmf/ kvm:\$grpname gu=r
}
gb.newvm()
{
    declare -a Tmp
    declare -a Res
    local i help=" [virtual size of vm] [opt:vm name eg: mars def:vmX]
    [opt: userdefined suffix e.g:20]"
    local destdir name suffix=0
    local prefix='vm'
    local size=\${1:?\$help}
    local vmname=\${2}
    local user_suffix=\${3}
    local dir=${guesthomedir}
#    set -x
    $sudo $mkdir -p \$dir
    $sudo $chown kvm:kvm \$dir
    $sudo $chmod g=rx \$dir
    Tmp=(\$($sudo $find \${dir} -maxdepth 1 -type d))
    Res=(\${Tmp[@]//\/srv\/kvm\/\$prefix/})
    echo \${Res[@]}
    for i in \${Res[@]};do
        [[ "\$i" =~ [[:digit:]]+ ]] || continue
        [[ "\$i" -le "\$suffix" ]] && continue
        suffix="\$i"
    done
    if [[ -n "\${user_suffix}" && \$suffix -lt "\${user_suffix}" ]];then
        suffix=\$user_suffix
    else
        suffix=\$((suffix + 1))
    fi
    name="\${prefix}\${suffix}"
    destdir="\${dir}/\${name}"
    gb.add.group.random-gid \${name}
    gb.add.user2group \$USER \${name}
    $sudo $mkdir -p \${destdir}/conf \
    \${destdir}/iso \${destdir}/ovmf \
    \${destdir}/socks \${destdir}/vbios
    $sudo $cp $ovmfdir/OVMF_CODE.4m.fd \${destdir}/ovmf/OVMF_CODE.fd
    $sudo $cp $ovmfdir/OVMF_VARS.4m.fd \${destdir}/ovmf/OVMF_VARS.fd
    gb.perm \${name}
    gb.create.img \${name} \${size}
    if [[ -z "\${vmname}" ]];then
        set +x
        return 1
    fi
    $sudo $mv \${destdir}/\${name}.qcow2 \${destdir}/\${vmname}.qcow2
    set +x
}
gb.perm()
{
    local help='[group e.g: vm1]'
    local group=\${1:?\$help}
    local dir=${guesthomedir}\${group}
    [[ -d "\$dir" ]] || {
        \builtin echo "invalid \$group" >&2
        return 1
    }
    gb.dirperm \$dir kvm:\$group u=rwx,g=rx,o=,+t 
    gb.fileperm \$dir kvm:\$group ug=rw,o=
    gb.fileperm \${dir}/iso kvm:\$group gu=r,o=
    gb.fileperm \${dir}/conf kvm:\$group gu=r,o=
    gb.fileperm \${dir}/vbios kvm:\$group gu=r,o=
    gb.fileperm \${dir}/ovmf/OVMF_VARS.fd kvm:\$group gu=r,o=
    gb.fileperm \${dir}/ovmf/OVMF_CODE.fd kvm:\$group gu=r,o=
}
gb.fileperm()
{
    local help='[dir | file] [user:group] [fileperm]'
    local dir=\${1:?\$help}
    local ownership=\${2:?\$help}
    local fileperm=\${3:?\$help}
    [[ \$($id -u) == 0 ]] || local cmd=$sudo
    \$cmd $find -P \$dir ! -type d ! -type l -exec $chown \$ownership {} \;
    \$cmd $find -P \$dir ! -type d ! -type l -exec $chmod \$fileperm {} \;
}
gb.dirperm()
{
    local help='[dir] [user:group] [dirperm]'
    local dir=\${1:?\$help}
    local ownership=\${2:?\$help}
    local dirperm=\${3:?\$help}
    [[ -d \${dir} ]] || return
    [[ \$($id -u) == 0 ]] || local cmd=$sudo
    \$cmd $find -P \$dir -type d -exec $chown \$ownership {} \;
    \$cmd $find -P \$dir -type d -exec $chmod \$dirperm {} \;
}
gb.create.img()
{
    local help='[user] [size] [opt:format def:qcow2]'
    local user=\${1:?\$help}
    local size=\${2:?\$help}
    local format=\${3:-qcow2}
    local dir=${guesthomedir}/\${user}
    local name=\${user}
    [[ -d \${dir} ]] || {
        \builtin echo "invalid name \$user" >&2
        return
    }
    $sudo $qemu_img create -f \${format} \${dir}/\${name}.\${format} \${size}
    $sudo $chown kvm:\$user \${dir}/\${name}.\${format}
    $sudo $chmod u=rw,g=rw,o= \${dir}/\${name}.\${format}
    $sudo $cp \${dir}/ovmf/OVMF_VARS.fd \${dir}/ovmf/\${name}_OVMF_VARS.fd
    $sudo $chown kvm:\$user \${dir}/ovmf/\${name}_OVMF_VARS.fd
    $sudo $chmod u=rw,g=rw,o= \${dir}/ovmf/\${name}_OVMF_VARS.fd
    $sudo $qemu_img info \${dir}/\${name}.\${format}
}
gb.mount.qcow2()
{
$cat<<MOUNTQCOW2
    usage:
    \$FUNCNAME [qcow2 file]
    mount /dev/nbd0pX /mnt/X 
    Then:
    gb.unmount.qcow2
MOUNTQCOW2
    local file=\${1:?[qcow2 file]}
    $grep -E -q 'nbd' <<<\$($lsmod) || $sudo $modprobe nbd max_part=16
    $sudo $qemu_nbd -c /dev/nbd0 \${file}
    $sudo parted /dev/nbd0 print
}
gb.unmount.qcow2()
{
    local mp=\${1:?[mountpoint] unmount and disconnect /dev/nbd0}
    mp=\$($realpath \$mp)
    $sudo $umount -fq \$mp
    $sudo $qemu_nbd -d /dev/nbd0
    $sudo $modprobe --remove --verbose nbd
}
gb.qemu.help()
{
    local arg help='[option: eg: -device] [opt driver: eg:virtio-net-pci]'
    local arg1=\${1} 
    local arg2=\${2}
    if [[ -n "\$arg2" ]];then
        arg="\$arg1 \$arg2,help"
    elif [[ -n "\$arg1" ]];then
        arg="\$arg1 help"
    else
        arg='-h'
    fi
    $qemu_system_x86_64 \$arg | le
}
gb.exclude()
{
    $cat<<-GOEXCLUDE>.git/info/exclude
dist/*.png
GOEXCLUDE
}
SUB
)
}
guestbridge.substitute
builtin unset -f guestbridge.substitute

