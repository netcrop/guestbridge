# Guestbridge
Guest Bridge is a Kernel Virtual Machine Configuration script, written in Bash/SHELL.

  It can be used to create and run KVM guest virtual machine.
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
eva > guestbridge.reconfig
eva > guestbridge.info
eva > guestbridge.loadmod
eva > guestbridge.install distro.iso distro.raw localhost:0
eva > guestbridge.tap.run sample/vm distro.raw br0 enp2s0
eva > guestbridge.socks distro info name
```

## Recommended usage.
Add
```
source guestbridge/guestbridge.sh
```
inside ~/.bashrc

## For developers

We use rolling releases.

## Reporting a bug and security issues

github.com/netcrop/guestbridge/issues

## License

[GNU General Public License version 2 (GPLv2)](https://github.com/netcrop/guestbridge/blob/master/LICENSE)
