# Guestbridge
Guest Bridge is a Kernel Virtual Machine Configuration script, written in Bash/SHELL.
it is used for create and run KVM guest virtual machine.
## Install, maintain and uninstall

* For linux/unix system:  
required commands and packages:
Bash version 4.4+
coreutils
modprobe
lsmod
ethtool
iproute2
grub
qemu-headless
pciutils
socat
sudo
[Perl File chmod](https://github.com/xenoterracide/File-chmod/blob/master/lib/File/chmod.pm)
```
* Checkout distro specific Releases
eva > git branch -avv
* arch
  master
eva > git checkout arch
Switched to branch arch

eva > cd guestbridge
eva > source guestbridge.sh
# Follow the instruction from this command.
eva > gb.info
...
eva > gb.run [GUEST CONFIG FILE] [GUEST IMAG QCOW2/RAW] [BRIDGE] [NETWORK INTERFACE]
eva > gb.socks /srv/kvm/socks/[GUEST IMAG SOCKS FILE] info name
```

## For developers

We use rolling releases.

## Reporting a bug and security issues

github.com/netcrop/guestbridge/pulls

## License

[GNU General Public License version 2 (GPLv2)](https://github.com/netcrop/guestbridge/blob/master/LICENSE)
