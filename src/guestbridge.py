#!/bin/env -S PATH=/usr/local/bin:/usr/bin python3 -I -B
import sys
sys.path.append(r'/usr/local/lib/python/guestbridge/')
import vfio
import qemu
import qmp
import bdf
class Guestbridge(qemu.Qemu,vfio.Vfio, qmp.Qmp, bdf.Bdf):
    def __init__(self,*argv):
        vfio.Vfio.__init__(self,*argv)
        qemu.Qemu.__init__(self,*argv)
        qmp.Qmp.__init__(self,*argv)
        bdf.Bdf.__init__(self,*argv)


if __name__ == '__main__':
    target = Guestbridge(sys.argv)
    target.setfun()
    if target.option not in target.fun:target.usage()
    target.fun[target.option]()
