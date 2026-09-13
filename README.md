    ## guestbridge:
    Guest Bridge is a Kernel Virtual Machine Configuration script, written in Bash/Python. Supporting GPU, Mouse, Keyboard, USB, Network pass through via vfio-pci to guest OS,
    and automatic starting VM. Meanwhile the host OS remain headless. Communication with guests via Qemu QMP and SSH. Administrator can therefore maintain a minimal footprint
    on host OS and keep it secure.

    * Prerequest
    gb.prerequest
    * find modules
    inside /usr/lib/modules/

    * avaliable modules
    list /lib/modules/
    
    * kernel module loaded ?
    lsmod |grep -E kvm|virtio
    gb.loadmodall
    gb.reconfig
    gb.dirperm

    * add system user and group kvm
    gb.user.add.system

    ## Pcie pass through:
    * Enable hugepages
    gb.hugepages
    * Enable VT-D/IOMMU in BIOS.
    * Update grub
    gb.grub
    * Non-root pci passthrough by allowing  Admin="$USER" user lock memory limits.
    * And Systemd LimitMEMLOCK
    gb.limits

    * show pci device id
    gb.lspci

    * Bind vfio-pci to pci device as kernel module.
    * Load module precedence.
    gb.modprobconfig

    * Restart Host Computer and verify IOMMU been enabled.
    dmesg|grep -E IOMMU
    * List iommu group
    gb.iommu

    * Bind devices with/without pass through in the same iommu group Verify Binded vfio-pci devices
    gb.lspci

    * Find out BDF of the Nic for pass through
    gb.bdf

    * Configure and install guest config file
    gb.vm.reconfig
    
    * Install python script
    gb.py.install

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
