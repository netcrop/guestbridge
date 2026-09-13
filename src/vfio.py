#!/bin/env -S PATH=/usr/local/bin:/usr/bin python3 -I -B
import sys,subprocess,re,glob
from collections import namedtuple
sys.path.append(r'/usr/local/lib/python/guestbridge/')
import toolset
class Vfio(toolset.Toolset):
    def __init__(self,*argv):
        if hasattr(self,'vfio'):return
        toolset.Toolset.__init__(self,*argv)

    def iommu(self):
        '''.'''
        iommu_res = glob.glob(self.vfio.pattern['device'])
        lspci_res = {}
        group = {}
        lspci = {}
        res = {}
        cmd = 'lspci -nn'
        self.run(cmd,stdout=subprocess.PIPE,exit_errorcode=-1)
        lspci_res = self.proc.stdout.split('\n')
        for l in iommu_res:
            match = re.search(self.vfio.pattern['combine'],l)
            if not match:continue
            group[match.group(2)] = match.group(1)
        for l in lspci_res:
            match = re.search(self.vfio.pattern['lspci'],l)
            if not match:continue
            lspci[match.group(1)] = \
            match.group(2) + match.group(2) + "\n" + match.group(4)
        for key,value in group.items():
            if value not in res:
                res[value] = "[" + key + "] " + lspci[key] + "\n"
            else:
                res[value] += "[" + key + "] " + lspci[key] + "\n"
        res = dict(sorted(res.items(),key=lambda item: int(item[0])))
        for key,value in res.items():
            print("iommu group: " + key)
            print(value)
if __name__ == '__main__':
    target = Vfio(sys.argv)
    target.setfun()
    if target.option not in target.fun:target.usage(target)
    target.fun[target.option]()
