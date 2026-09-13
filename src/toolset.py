#!/bin/env -S PATH=/usr/local/bin:/usr/bin python3 -I -B
import subprocess,sys,inspect,os,getpass,fcntl,grp,shlex
from collections import namedtuple
from collections import defaultdict
class Toolset():
    def __init__(self,*argv):
        if hasattr(self, 'argv'):return
        self.argv = argv
        self.args = list(argv[0])
        self.argc = len(self.args)
        if self.argc == 1: self.args.append(None)
        self.option = self.args[1]
        self.fun = {}
        self.permit = ''
        for gid in os.getgroups():
            try:
                grp.getgrgid(gid)
            except KeyError:continue
            if grp.getgrgid(gid).gr_name != 'wheel':continue
            self.permit = '/bin/sudo'
        self.proc = None
        for base in self.__class__.__bases__:
            if base.__name__ == 'object':continue
#            self.debug(base.__name__ + str(self.argv), debugging = self.debugging)
        self.debugging = 0
        self.toolset = namedtuple('toolset','uid lockfile backuplock username guesthomedir pci_conf vlan_conf')\
        (
        '',
        '/run/lock/guestbridge',
        '/run/lock/backup',
        getpass.getuser(),
        '/srv/kvm/',
        '/srv/kvm/pci.conf',
        '/srv/kvm/vlan.conf'
        )

        self.pattern = namedtuple('pattern','bdf macaddress short_bdf_vendor_device_id indexedname interface long_bdf')\
        (
        r'([0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-7])',
        r'([0-9a-z][0-9a-z]:[0-9a-z][0-9a-z]:[0-9a-z][0-9a-z]:[0-9a-z][0-9a-z]:[0-9a-z][0-9a-z]:[0-9a-z][0-9a-z])',
        r'^([0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-7])\s.*\s\[([0-9a-fA-F]{4}:[0-9a-fA-F]{4})\]',
        r'^\d+:\s+([\@\w_-]+):',
        r'^\d+:\s+([\@\w_-]+):',
        r'0000:([0-9][0-9]\:[0-9][0-9]\.[0-9])'
        )
        self.config = namedtuple('config',\
        'pci content option result device sockspath bridge tap vlan socksdir guestcfg guestname')\
        ({},[],defaultdict(dict),[],defaultdict(dict),[],{},{},{},[],[],[])

        self.driver = namedtuple('driver','pcidir fleet')([],{})
        self.driver.pcidir.append('/sys/bus/pci/drivers/')
        self.driver.fleet.update({'xhci_pci':'xhci_hcd'})
        self.driver.fleet.update({'xhci-pci':'xhci-hcd'})
        self.driver.fleet.update({'i2c_i801':'i801_smbus'})
        self.driver.fleet.update({'intel_spi_pci':'intel-spi'})


        self.qmp = namedtuple('qmp','message color')(defaultdict(dict),{})
        self.qmp.message.update({'cap':'{ "execute": "qmp_capabilities" }\n'})
        self.qmp.message.update({'status':'{ "execute": "query-status" }\n'})
        self.qmp.message.update({'shutdown':'{ "execute": "system_powerdown" }\n'})
        self.qmp.message.update({'quit':'{ "execute": "quit" }\n'})
        self.qmp.message.update({'stop':'{ "execute": "stop" }\n'})
        self.qmp.message.update({'cont':'{ "execute": "cont" }\n'})

        self.qmp.color.update({'"running"':'green'})
        self.qmp.color.update({'"shutdown"':'white'})
        self.qmp.color.update({'"clean up"':'yellow'})
        self.qmp.color.update({'"internal-error"':'red'})
        self.qmp.color.update({'"paused"':'yellow'})

        self.tpm = namedtuple('tpm','socksdir sockspath')([],[])

        self.vfio = namedtuple('vfio','pattern')({})
        self.vfio.pattern.update({'device': r'/sys/kernel/iommu_groups/*/devices/*'})
        self.vfio.pattern.update({'bdf':r'([a-z0-9][a-z0-9]:[a-z0-9][a-z0-9].[a-z0-9])'})
        self.vfio.pattern.update({'number': r'([0-9]+)'})
        self.vfio.pattern.update({'combine':rf'/sys/kernel/iommu_groups/{self.vfio.pattern["number"]}/devices/0000:{self.vfio.pattern["bdf"]}\n*'})
        self.vfio.pattern.update({'lspci':rf'{self.vfio.pattern["bdf"]}\s+([^:]+)(:)\s+(.*)\n*'})


    def run(self,cmd='',infile='',outfile='',stdin=None,stdout=None,
        text=True,pass_fds=(),exit_errorcode='',shell=False,debugging=0):
        try:
            proc = None
            emit = __file__ + ':' + sys._getframe(1).f_code.co_name + ':' \
            + str(sys._getframe(1).f_lineno)
            if infile != '': stdin = open(infile,'r',encoding='utf-8')
            if outfile != '': stdout = open(outfile,'w',encoding='utf-8')
            for line in cmd.splitlines():
                cmd = shlex.split(line)
                proc = subprocess.run(cmd,
                stdin=stdin,stdout=stdout,text=text,check=True,
                pass_fds=pass_fds,shell=shell)
                if infile != '': stdin.close()
                if outfile != '': stdout.close()
                if not isinstance(proc,subprocess.CompletedProcess):
                    self.debug(info='end 1',emit=emit,debugging=debugging)
                    proc = None
                    print('faild: ' + " ".join(cmd),file=sys.stderr)
                    sys.exit(1)
                if isinstance(proc.stdout,str):
                    proc.stdout = proc.stdout.rstrip('\n')
                    self.debug(info='end 2',emit=emit,debugging=debugging)
                    self.proc = proc
        except subprocess.CalledProcessError as e:
            emit += ':' + str(e.returncode)
            print('faild: ' + " ".join(cmd),file=sys.stderr)
            if exit_errorcode == '':
                if e.returncode != 0:
                    self.debug(info='end 3: ',emit=emit,debugging=debugging)
                    sys.exit()
            elif e.returncode == exit_errorcode:
                self.debug(info='end 4',emit=emit,debugging=debugging)
                sys.exit()
            else:
                proc = None
                sys.exit(1)

    def debug(self,info='',emit='',debugging=0):
        if not self.debugging and not debugging: return
        emit = sys._getframe(1).f_code.co_name + ':' \
        + str(sys._getframe(1).f_lineno) + ':' + info + ':' + emit
        print(emit,file=sys.stderr)

    def setfun(self):
#        self.debug(__name__,debugging=self.debugging)
#        print(dict(inspect.getmembers(self,predicate=inspect.ismethod)))
        self.fun.update(dict(inspect.getmembers(self,predicate=inspect.ismethod)))

    def usage(self):
        if self.option in self.fun:
            print(self.option,self.fun[self.option].__doc__)
        else:
            for key,value in self.fun.items():
                if not value.__doc__: continue
                if key.startswith('_'):continue
                if value.__doc__.startswith('_'):continue
                print(f"{key:16} {value.__doc__}")
        sys.exit(1)

    def funlock(self,funname=print):
        if not os.path.exists('/run/lock'):
            cmd = self.permit + ' /bin/mkdir -p /run/lock'
            self.run(cmd)
            cmd = self.permit + ' /bin/chmod go=rx /run/lock'
            self.run(cmd)
        if not os.path.exists(self.toolset.lockfile):
            cmd = self.permit + ' touch ' + self.toolset.lockfile
            self.run(cmd)
            cmd = self.permit + ' chmod go=r ' + self.toolset.lockfile
            self.run(cmd)
        with open(self.toolset.lockfile,'r',encoding='utf-8') as fh:
            fcntl.flock(fh,fcntl.LOCK_EX | fcntl.LOCK_NB)
            funname()
            fcntl.flock(fh,fcntl.LOCK_UN)
