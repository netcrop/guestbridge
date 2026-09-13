#!/bin/env -S PATH=/usr/local/bin:/usr/bin python3 -I -B
import os,sys,subprocess,glob,time
from collections import namedtuple
sys.path.append(r'/usr/local/lib/python/guestbridge/')
import toolset
class Tpm(toolset.Toolset):
    def __init__(self,*argv):
        if hasattr(self,'tpm'):return
        toolset.Toolset.__init__(self,*argv)

    def swtpm(self):
        '''[opt: guestname e.g: vm2-sun] start swtpm server process.'''
        for name in ['']:
            if self.config.guestname:continue
            if self.argc < 3:
                print('guestname required.',file=sys.stderr)
                sys.exit(1)
            if os.path.exists(self.args[2]):continue
            name = self.args[2].split('-')
            if len(name) != 2 or not name[0] or not name[1]:
                print('invalid guestname: ' + self.args[2],file=sys.stderr)
                sys.exit(1)
            self.config.guestname.append(name[0])
            self.config.guestname.append(name[1])
            if not glob.glob(self.toolset.guesthomedir[0] + name[0]):continue
            if os.path.exists(self.toolset.guesthomedir[0] + name[0] + '/swtpm/' + name[0]):
                print(self.toolset.guesthomedir[0] + name[0] + '/swtpm/' + name[0] + " already exits.",file=sys.stderr)
                sys.exit(1)
            self.config.guestname.append(name[0])
            self.tpm.socksdir.append(self.toolset.guesthomedir[0] + name[0] + '/swtpm/')
            self.tpm.sockspath.append(self.toolset.guesthomedir[0] + name[0] + '/swtpm/' + name[0])
        cmd = self.permit + ' /bin/mkdir -p '  + self.tpm.socksdir[0]
        self.run(cmd)
        cmd = self.permit + ' /bin/chown ' + 'kvm:' + self.config.guestname[0] + ' ' + self.tpm.socksdir[0]
        self.run(cmd)
        cmd = self.permit + ' /bin/chmod ' + 'u=rwx,g=rwx,o= ' + self.tpm.socksdir[0]
        self.run(cmd)
        cmd = '/bin/swtpm socket --tpmstat dir=' + self.tpm.socksdir[0] \
        + ' --ctrl type=unixio,path=' + self.tpm.sockspath[0] + ' --tpm2 --log level=20'
        subprocess.Popen(cmd.split())
        time.sleep(1)
        cmd = self.permit + ' /bin/chown ' + 'kvm:' + self.config.guestname[0] + ' ' + self.tpm.sockspath[0]
        self.run(cmd)
        cmd = self.permit + ' /bin/chmod ' + 'u=rw,g=rw,o= ' + self.tpm.sockspath[0]
        self.run(cmd)
if __name__ == '__main__':
    target = Tpm(sys.argv)
    target.setfun(target)
    if target.option not in target.fun:target.usage(target)
    target.fun[target.option]()
