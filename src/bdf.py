#!/bin/env -S PATH=/usr/local/bin:/usr/bin python3 -I -B
import sys,subprocess,re
sys.path.append(r'/usr/local/lib/python/guestbridge/')
import toolset
class Bdf(toolset.Toolset):
    def __init__(self,*argv):
        if hasattr(self,'bdf'):return
        toolset.Toolset.__init__(self,*argv)

    def find_bdf_by_interface(self):
        '''[interface]'''
        if self.argc < 3:self.usage()
        interface = self.args[2]
        cmd = '/usr/sbin/ethtool --driver ' + interface
        self.run(cmd,stdout=subprocess.PIPE)
        res = self.proc.stdout.split()
        for i in res:
            if i != 'bus-info:':continue
            print(res[res.index(i) + 1])
            return

    def find_bdf_by_vendor_device_id(self,input=''):
        '''[ vendor_id:device_id eg: 1002:7550 ]'''
        if self.argc < 3:self.usage()
        input = self.args[2]
        cmd = f"/usr/sbin/lspci -nn"
        self.run(cmd,stdout=subprocess.PIPE)
        res = self.proc.stdout.split('\n')
        bdf_vendor_device = {}
        for line in res:
            match = re.search(self.pattern.short_bdf_vendor_device_id,line)
            if match:
                bdf_vendor_device[match.group(1)] = match.group(2)
                continue
        for key, value in bdf_vendor_device.items():
            if input == value: print(key)

    def find_bdf_by_mac_address(self,mac_address=''):
        cmd = 'ip add show'
        self.run(cmd,stdout=subprocess.PIPE)
        res = self.proc.stdout.split('\n')
        name = []
        mac = []
        interface = ''
        index = -1
        for line in res:
            match = re.search(self.pattern.indexedname,line)
            if match:
                index += 1
                name += [ {index:match.group(1)} ]
                continue
            match = re.search(self.pattern.macaddress,line)
            if match:
                mac += [ {index:match.group(1)} ]
                continue
        for i in list(range(len(mac))):
            if next(iter(mac[i].values())) != mac_address: continue
            for j in list(range(len(name))):
                if next(iter(name[j].keys())) != i:continue
                interface = next(iter(name[j].values()))
                cmd = '/usr/sbin/ethtool --driver ' + interface
                self.run(cmd,stdout=subprocess.PIPE)
                res = self.proc.stdout.split()
                for i in res:
                    if i != 'bus-info:':continue

if __name__ == '__main__':
    target = Bdf(sys.argv)
    target.setfun()
    print('bdf')
    if target.option not in target.fun:target.usage(target)
    target.fun[target.option]()
