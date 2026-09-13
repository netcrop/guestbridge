#!/bin/env -S PATH=/usr/local/bin:/usr/bin python3 -I -B
import sys,subprocess,re
sys.path.append(r'/usr/local/lib/python/guestbridge/')
import config
class Device(config.Config):
    def __init__(self,*argv):
        if hasattr(self,'device'):return
        config.Config.__init__(self,*argv)
        self.device = None

    #########################################
    # bind/rebind devices to original drivers
    #########################################
    def __rebinding(self):
        match = ''
        real = {}
        module = {}
        cmd = 'lspci -vmk '
        self.run(cmd,stdout=subprocess.PIPE)
        for i in self.proc.stdout.split('\n\n'):
            lspci = {}
            for j in i.split('\n'):
                (key,value) = j.split(':',1)
                if key.strip() in lspci:continue
                lspci[key.strip()] = value.strip()
            if 'Device' not in lspci:continue
            if 'Driver' in lspci:
                real[lspci['Device']] = lspci['Driver']
            if 'Module' not in lspci:continue
            if lspci['Module'] == 'xhci_pci':
                module[lspci['Device']] = 'xhci_hcd'
            else:
                module[lspci['Device']] = lspci['Module']
        for key,value in self.config.device.items():
            match = re.search('(amd|gpu|nouveau)',module[key])
            if match is not None:continue
            if key not in real:
                value = value.replace('-','_')
                if key not in module: continue
                cmd = self.permit + ' modprobe ' + module[key]
                self.run(cmd)
#                print(key,module[key])
                self.bind(bdf=key,binddriver=module[key])
                continue
            if key not in module:
                self.unbind(bdf=key,unbinddriver=real[key])
                continue
            if module[key] == real[key]:continue
            cmd = self.permit + ' modprobe ' + module[key]
            self.run(cmd)
            self.rebind(bdf=key,unbinddriver=real[key],binddriver=module[key])


    #######################################
    # bind/rebind devices to vfio drivers
    #######################################
    def __binding(self):
        real = {}
        module = {}
        match = ''
        cmd = 'lspci -vmk '
        self.run(cmd,stdout=subprocess.PIPE)
        for i in self.proc.stdout.split('\n\n'):
            lspci = {}
            for j in i.split('\n'):
                (key,value) = j.split(':',1)
                if key.strip() in lspci:continue
                lspci[key.strip()] = value.strip()

            if 'Device' not in lspci:continue
            if 'Driver' in lspci:
                real[lspci['Device']] = lspci['Driver']
            if 'Module' in lspci:
                module[lspci['Device']] = lspci['Module']
#        print(real)
#        print(module)
        for key,value in self.config.device.items():
            if key not in real:
                value = value.replace('-','_')
                cmd = self.permit + ' modprobe ' + value
                self.run(cmd)
                self.bind(bdf=key,binddriver=value)
                continue
            self.bind(bdf=key,binddriver=value)
            if value == real[key]:continue
            match = re.search('(amd|gpu|nouveau)',real[key])
            if match is not None:
                self.rebind(bdf=key,unbinddriver=real[key],binddriver=value)
                cmd = self.permit + ' modprobe --remove ' + real[key]
#                self.run(cmd)
                continue
            self.rebind(bdf=key,unbinddriver=real[key],binddriver=value)

    def binding(self):
        '''[config file]'''
        if self.argc < 3: self.usage()
        self.configready()
        self.__binding()

    def rebinding(self):
        '''[config file]'''
        if self.argc < 3: self.usage()
        self.configready()
        self.__rebinding()


if __name__ == '__main__':
    target = Device(sys.argv)
    target.setfun()
    if target.option not in target.fun:target.usage(target)
    target.fun[target.option]()
