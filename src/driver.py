#!/bin/env -S PATH=/usr/local/bin:/usr/bin python3 -I -B
import os,sys,subprocess,re
from collections import namedtuple
sys.path.append(r'/usr/local/lib/python/guestbridge/')
import toolset
class Driver(toolset.Toolset):
    def __init__(self,*argv):
        if hasattr(self,'driver'):return
        toolset.Toolset.__init__(self,*argv)

    def prerebind(self):
        '''[bdf] [vfio-pci]   [amdgpu | ixgbevf ixgbe ehci-pci ohci-pci xhci-hcd vfio-pci igb snd_hda_intel]'''
        if self.argc < 5:self.usage()
        self.rebind(bdf=self.args[2],unbinddriver=self.args[3],binddriver=self.args[4])

    def rebind(self,bdf='',unbinddriver='',binddriver=''):
        if not unbinddriver:print('invalid unbind driver: ' + unbinddriver);sys.exit(1)
        if not binddriver:print('invalid bind driver: ' + binddriver);sys.exit(1)
        self.unbind(bdf,unbinddriver)
        self.bind(bdf,binddriver)

    def preunbind(self):
        '''[bdf] [ixgbevf ixgbe ehci-pci ohci-pci xhci-hcd vfio-pci igb snd_hda_intel] [...]'''
        if self.argc < 4:self.usage()
        self.unbind(bdf=self.args[2],unbinddriver=self.args[3])

    def unbind(self,bdf='',unbinddriver=''):
        if not unbinddriver:print('invalid unbind driver: ' + unbinddriver);sys.exit(1)
        match = re.search(self.pattern.bdf,bdf)
        if match is None:
            print('Already passed through Or invalid bdf: ' + bdf)
            return
#            sys.exit(1)
        bdf = '0000:' + bdf
        if not os.path.exists(os.path.join(self.driver.pcidir[0],unbinddriver)):
            unbinddriver.replace('_','-')
        unbindpath = os.path.join(self.driver.pcidir[0],unbinddriver,'unbind')
        if not os.path.exists(unbindpath):print('non exists: ' + unbindpath);sys.exit(1)
        cmd = self.permit + ' chown ' + self.toolset.username + ' ' + unbindpath
        self.run(cmd)
        try:
            with open(unbindpath,'w',encoding='utf-8') as fh:
                print(bdf,file=fh)
        except OSError: sys.exit(1)
        cmd = self.permit + ' chown root ' + unbindpath
        self.run(cmd)
#        cmd = 'lspci -s ' + bdf + ' -k'
#        self.run(cmd)

    def prebind(self):
        '''[bdf] [ixgbevf ixgbe ehci-pci ohci-pci xhci-hcd vfio-pci igb snd_hda_intel] [...]'''
        if self.argc < 4:self.usage()
        self.bind(bdf=self.args[2],binddriver=self.args[3])

    def bind(self,bdf='',binddriver=''):
        if not binddriver:print('invalid bind driver: ' + binddriver);sys.exit(1)
        match = re.search(self.pattern.bdf,bdf)
        if match is None:
            print('Already passed through Or invalid bdf: ' + bdf)
            return
#            sys.exit(1)
        bdf = '0000:' + bdf
        if binddriver in self.driver.fleet:
            binddriver = self.driver.fleet[binddriver]
        if not os.path.exists(os.path.join(self.driver.pcidir[0],binddriver)):
            binddriver = binddriver.replace('_','-')
        os.path.join(self.driver.pcidir[0],binddriver)
        idpath = os.path.join(self.driver.pcidir[0],binddriver,'new_id')
        if not os.path.exists(idpath):print('non exists: ' + idpath);sys.exit(1)
        cmd = 'lspci -s ' + bdf + ' -n'
        self.run(cmd,stdout=subprocess.PIPE)
        if not self.proc.stdout:
            print('Invalid: ' + cmd, file=sys.stderr)
            sys.exit()
        deviceid = self.proc.stdout.split()[2].replace(':',' ')

        cmd = self.permit + ' chown ' + self.toolset.username
        cmd += ':' + self.toolset.username + ' ' + idpath
        self.run(cmd)
        try:
            with open(idpath,'w',encoding='utf-8') as fh:
                print(deviceid,file=fh)
        # ignore error.
        except IOError:pass
        cmd = self.permit + ' chown root:root ' + idpath
        self.run(cmd)

        bindpath = os.path.join(os.path.join(self.driver.pcidir[0],binddriver,'bind'))
        if not os.path.exists(bindpath):print('non exists: ' + bindpath);sys.exit(1)
        cmd = self.permit + ' chown ' + self.toolset.username
        cmd += ':' + self.toolset.username + ' ' + bindpath
        self.run(cmd)
        try:
            with open(bindpath,'w',encoding='utf-8') as fh:
                print(bdf,file=fh)
        # ignore error.
        except IOError:pass
        cmd = self.permit + ' chown root ' + bindpath
        self.run(cmd)
#        cmd = 'lspci -s ' + bdf + ' -k'
#        self.run(cmd)

if __name__ == '__main__':
    target = Driver(sys.argv)
    target.setfun()
    if target.option not in target.fun:target.usage(target)
    target.fun[target.option]()
