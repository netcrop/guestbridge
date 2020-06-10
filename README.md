# Guestbridge
Guest Bridge is a Kernel Virtual Machine Configuration script, written in Bash/Perl.
Supporting GPU (Mouse, Keyboard, USB, Network) pass through via PCIE to guest OS,
and automatic release devices back to host OS.
Meanwhile the host OS remain headless (in case single GPU,keyboard and mouse setup) communication with guests via SSH.
Administrator can therefore maintain a minimal footprint on host OS and keep it secure.

## Install, maintain and uninstall

* For linux/unix system:  
required commands and packages:
Bash version 4.4+
Perl version 5.30+
coreutils
modprobe
lsmod
ethtool
iproute2
grub
qemu-headless
pciutils
usbutils
socat
flock
sudo
```
* Checkout distro specific Releases
> git branch -avv
* arch
  master
> git checkout arch
Switched to branch arch

> cd guestbridge
> source guestbridge.sh
# Follow the instruction from this command.
> gb.info
...
# guest config file follow the same syntax as qemu command line.
> cat sample/arch
...
# Install Systemd cron service for auto release devices passed through to guests.
> gb.croninstall
...
# Start guest with bridged network tap or pass through PCI devices via config file
> gb [GUEST COINFIG FILE]
...
# Communicate with guests via socket.
> gb.socks [GUEST NAME] info name
```

## For developers

We use rolling releases.

## Reporting a bug and security issues

github.com/netcrop/guestbridge/pulls

## License

[GNU General Public License version 2 (GPLv2)](https://github.com/netcrop/guestbridge/blob/master/LICENSE)
