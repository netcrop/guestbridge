#!/bin/env -S PATH=/usr/local/bin:/usr/bin python3 -I
import re,tempfile,resource,glob,io,subprocess,sys
import os,socket,getpass,random,pwd,grp,hashlib
import fcntl,stat,time,grp,pytz
from datetime import datetime
class Guestbridge:
    def __init__(self,*argv):
        self.message = {'-h':' print this help message.',
        '-s':' [vm config file] startvm.',
        '-t':' test ',
        '-b':' [bdf] [bind driver: ehci-pci/ohci-pci/xhci-hcd/vfio-pci] ',
        '-u':' [bdf] [unbind driver: ehci-pci/ohci-pci/xhci-hcd/vfio-pci] ',
        '-r':' [bdf] [unbind driver] [bind driver] : ehci-pci/ohci-pci/xhci-hcd/vfio-pci] ',
        '-m':' new mac address ',
        '-c':' cron ' }
        self.argv = argv
        self.args = argv[0]
        self.argc = len(self.args)
        if self.argc == 1: self.usage()
        self.option = { '-h':self.usage,'-t':self.test,
        '-c':self.precron, '-s':self.prestartvm, '-b':self.prebind,
        '-u':self.preunbind, '-r':self.prerebind, '-m':self.newmac}

        self.hostname = socket.gethostname()
        self.uid = os.getuid()
        self.username = getpass.getuser()
        self.userhost = self.username + '@' + self.hostname
        self.tmpdir = '/var/tmp/'
        self.usrgrp = ''
        self.debugging = DEBUGGING
        self.gbdir = 'GUESTBRIDGEDIR'
        self.lockfile = '/run/lock/guestbridge'
        self.backuplock = '/run/lock/backup'
        self.socksdir = 'SOCKSDIR'
        self.vfiodir = 'VFIODIR'
        self.virtiofsdsocksdir = 'VIRTIOFSDSOCKSDIR'
        self.pcidir = 'PCIDIR'
        self.permit = ''
        self.conditional = True
        self.config = {}
        self.real = {}
        self.module = {}
        self.wish = {}
        self.nic = {}
        self.cin = {}
        self.master = {}
        self.bdfpattern = '(..\:..\..)'
        self.b10t16 = '0123456789abcdef'
        self.macaddress = ''
        if self.uid != 0: self.permit = 'sudo'

    def prestartvm(self):
        self.funlock(funname=self.startvm)

    def precron(self):
        self.funlock(funname=self.cron)

    def status(self):
        path =self.socksdir + '/' + self.guestname
        if not os.path.exists(path):
            print('missing: ' + path);exit(1)
        cmd = self.permit + ' chown kvm:kvm ' + path
        self.run(cmd)
        cmd = self.permit + ' chmod gu=rw ' + path
        self.run(cmd)

    def start(self):
        cmd = self.permit + ' chmod 4755 /usr/local/bin/qemu'
        self.run(cmd)
        cmd = ' qemu -chroot /var/tmp/ -runas kvm ' + ' '.join(self.config)
        subprocess.Popen(cmd.split())
        cmd = self.permit + ' chmod 0755 /usr/local/bin/qemu'
        self.run(cmd)

    def perm(self):
        if len(self.mountpath) == 0:return
        for root,dirs,files in os.walk(self.virtiofsdsocksdir):
            for f in files:
                cmd = self.permit + ' chown :kvm ' + os.path.join(root,f)
                self.run(cmd)
                cmd = self.permit + ' chmod g=rw ' + os.path.join(root,f)
                self.run(cmd)
###########################################
# Unbridge/Untap network
###########################################
    def renetwork(self):
        cmd = 'bridge link'
        proc = self.run(cmd,stdout=subprocess.PIPE,exit_errorcode=-1)
        if proc == None:print('failed: ' + cmd);exit(1)
        for line in proc.stdout.split('\n'):
            if len(line) == 0:continue
            self.any = {}
            records = line.split(' ')
            for i in range(len(records)):
                self.match = re.search('master',records[i])
                if not self.match:continue
                self.any[records[i]] = records[i+1]
            records[1] = records[1].replace(':','')
            if 'master' not in self.any:continue
            self.nic[records[1]] = self.any['master']
            if self.any['master'] in self.cin:
                self.cin[self.any['master']] += ' ' + records[1]
            else:
                self.cin[self.any['master']] = records[1]
        self.any = {}
        for key,value in self.cin.items():
            self.match = re.search(self.guestname,value)
            if not self.match:continue
            self.any = value.split(' ')
            for i in range(len(self.any)):
                if not self.any[i] in self.tap:continue
                cmd = self.permit + ' ip tuntap delete dev ' + self.any[i] + ' mod tap'
                self.run(cmd)
###########################################
# Bridge/tap network
###########################################
    def network(self):
        cmd = 'ip -o link show'
        proc = self.run(cmd,stdout=subprocess.PIPE,exit_errorcode=-1)
        if proc == None:print('failed: ' + cmd);exit(1)
        for line in proc.stdout.split('\n'):
            self.any = {}
            records = line.split(' ')
            for i in range(len(records)):
                self.match = re.search('(permaddr|link/ether|master)',records[i]) 
                if not self.match:continue
                self.any[records[i]] = records[i+1]
            records[1] = records[1].replace(':','')
            if 'permaddr' in self.any:self.nic[self.any['permaddr']] = records[1]
            if 'link/ether' in self.any:self.nic[self.any['link/ether']] = records[1]
            if 'master' in self.any:self.master[records[1]] = self.any['master']

        # One physical nic belongs to only one bridge
        for key,value in self.nic.items():
            if not value in self.config_bridge:continue
            # Already has this bridge
            self.config_bridge.pop(value)
        # Filter out non exists physical nic from config bridge
        for key,value in self.config_bridge.items():
            if value in self.nic:continue
            self.config_bridge.pop(key)
        # Filter out impossible taps from config tap
        for key,value in self.tap.items():
            if value in self.nic:continue
            self.tap.pop(key)
        # Create bridges that are not already in place
        for key,value in self.config_bridge.items():
            if not value:continue
            if not value in self.nic:continue
            cmd = self.permit + ' ip address flush dev ' + self.nic[value] 
            self.run(cmd)
            cmd = self.permit + ' ip link add name ' + key + ' type bridge' 
            self.run(cmd)
            cmd = self.permit + ' ip link set ' + key + ' up' 
            self.run(cmd)
            cmd = self.permit + ' ip link set ' + self.nic[value] + ' down' 
            self.run(cmd)
            cmd = self.permit + ' ip link set ' + self.nic[value] + ' up' 
            self.run(cmd)
            cmd = self.permit + ' ip link set ' + self.nic[value] + ' master ' + key 
            self.run(cmd)
        # Filter out existing taps and bridge them
        for key,value in self.nic.items():
            if not value in self.tap:continue
            # already has this tap and it's also bridged.
            if value in self.master:
                self.tap.pop(value)
                continue
            self.tap[value] = self.tap[value].replace(':','')
            cmd = self.permit + ' ip link set dev ' + value + ' up'
            self.run(cmd)
            cmd = self.permit + ' ip link set ' + value + ' master ' + self.tap[value]
            self.run(cmd)
        # Add new taps and bridge them.
        for key,value in self.tap.items():
            cmd = self.permit + ' ip tuntap add dev ' + key + ' mode tap user ' + self.username
            self.run(cmd)
            cmd = self.permit + ' ip link set dev ' + key + ' up'
            self.run(cmd)
            cmd = self.permit + ' ip link set ' + key + ' master ' + value.replace(':','')
            self.run(cmd)

    #######################################
    # Virtiofsd 
    #######################################
    def virtiofsd(self):
        if len(self.mountpath) == 0:return
        cmd = self.permit + ' chmod 4755 /usr/lib/qemu/virtiofsd'
        self.run(cmd)
        for i in self.mountpath:
            sockspath = self.virtiofsdsocksdir + '/' + self.guestname + '-' + i.replace('/','@') + '.sock'
            if os.path.exists(sockspath):continue
            cmd = '/usr/lib/qemu/virtiofsd --syslog --socket-path=' + sockspath 
            cmd += ' --thread-pool-size=8 -o source=' + i
            subprocess.Popen(cmd.split())
        cmd = self.permit + ' chmod 0755 /usr/lib/qemu/virtiofsd'
        self.run(cmd)
 
    #######################################
    # Rebind 
    #######################################
 
    def prerebind(self):
        if self.argc < 5:self.usage(self.args[1])
        self.gb_rebind(bdf=self.args[2],unbinddriver=self.args[3],binddriver=self.args[4])

    def gb_rebind(self,bdf='',unbinddriver='',binddriver=''):  
        if not unbinddriver:print('invalid unbind driver: ' + unbinddriver);exit(1)
        if not binddriver:print('invalid bind driver: ' + binddriver);exit(1)
        self.gb_unbind(bdf,unbinddriver)
        self.gb_bind(bdf,binddriver)

    #######################################
    # Unbind 
    #######################################
 
    def preunbind(self):
        if self.argc < 4:self.usage(self.args[1])
        self.gb_unbind(bdf=self.args[2],unbinddriver=self.args[3])

    def gb_unbind(self,bdf='',unbinddriver=''):
        if not unbinddriver:print('invalid unbind driver: ' + unbinddriver);exit(1)
        self.match = re.search(self.bdfpattern,bdf)
        if self.match == None:print('invalid bdf: ' + bdf);exit(1)
        bdf = '0000:' + bdf
        if not os.path.exists(os.path.join(self.pcidir,unbinddriver)):
            unbinddriver.replace('_','-')
        unbindpath = os.path.join(self.pcidir,unbinddriver,'unbind')
        if not os.path.exists(unbindpath):print('non exists: ' + unbindpath);exit(1)
        cmd = self.permit + ' chown ' + self.username + ' ' + unbindpath
        self.run(cmd)
        try:
            with open(unbindpath,'w') as fh:
                print(bdf,file=fh)
        except:pass
        cmd = self.permit + ' chown root ' + unbindpath
        self.run(cmd)
#        cmd = 'lspci -s ' + bdf + ' -k'
#        self.run(cmd)

    #######################################
    # Bind 
    #######################################
 
    def prebind(self):
        if self.argc < 4:self.usage(self.args[1])
        self.gb_bind(bdf=self.args[2],binddriver=self.args[3])

    def gb_bind(self,bdf='',binddriver=''):
        if not binddriver:print('invalid bind driver: ' + binddriver);exit(1)
        self.match = re.search(self.bdfpattern,bdf)
        if self.match == None:print('invalid bdf: ' + bdf);exit(1)
        bdf = '0000:' + bdf
        if binddriver == 'xhci_pci':binddriver = 'xhci_hcd'
        if binddriver == 'xhci-pci':binddriver = 'xhci-hcd'
        if binddriver == 'i2c_i801':binddriver = 'i801_smbus'
        if binddriver == 'intel_spi_pci':binddriver = 'intel-spi'

        if not os.path.exists(os.path.join(self.pcidir,binddriver)):
            binddriver = binddriver.replace('_','-')
        driverpath = os.path.join(self.pcidir,binddriver)
        idpath = os.path.join(self.pcidir,binddriver,'new_id')
        if not os.path.exists(idpath):print('non exists: ' + idpath);exit(1)
        cmd = 'lspci -s ' + bdf + ' -n'
        proc = self.run(cmd,stdout=subprocess.PIPE)
        if proc == None:print('failed: ' + cmd );exit(1)
        id = proc.stdout.split()[2].replace(':',' ')

        cmd = self.permit + ' chown ' + self.username 
        cmd += ':' + self.username + ' ' + idpath
        self.run(cmd)
        try:
            with open(idpath,'w') as fh:
                print(id,file=fh)
        except:pass
        cmd = self.permit + ' chown root:root ' + idpath
        self.run(cmd)

        bindpath = os.path.join(os.path.join(self.pcidir,binddriver,'bind'))
        if not os.path.exists(bindpath):print('non exists: ' + bindpath);exit(1)
        cmd = self.permit + ' chown ' + self.username 
        cmd += ':' + self.username + ' ' + bindpath
        self.run(cmd)
        try:
            with open(bindpath,'w') as fh:
                print(bdf,file=fh)
        except:pass
        cmd = self.permit + ' chown root ' + bindpath
        self.run(cmd)
#        cmd = 'lspci -s ' + bdf + ' -k'
#        self.run(cmd)

    ########################################
    # bind/rebind devices to original drivers
    #######################################
    def redevice(self):
        cmd = 'lspci -vmk '
        proc = self.run(cmd,stdout=subprocess.PIPE)
        if proc == None:exit(1)
        for i in proc.stdout.split('\n\n'):
            self.lspci = {}
            for j in i.split('\n'):
                (key,value) = j.split(':',1)
                if key.strip() in self.lspci:continue
                self.lspci[key.strip()] = value.strip()
            if 'Device' not in self.lspci:continue
            if 'Driver' in self.lspci:
                self.real[self.lspci['Device']] = self.lspci['Driver']
            if 'Module' not in self.lspci:continue
            if self.lspci['Module'] == 'xhci_pci':
                self.module[self.lspci['Device']] = 'xhci_hcd'
            else:
                self.module[self.lspci['Device']] = self.lspci['Module']
        for key,value in self.wish.items():
            self.match = re.search('(amd|gpu|nouveau)',self.module[key])
            if self.match != None:continue
            if key not in self.real:
                value = value.replace('-','_')
                if key not in self.module: continue
                cmd = self.permit + ' modprobe ' + self.module[key]
                self.run(cmd)
                print(key,self.module[key])
                self.gb_bind(bdf=key,binddriver=self.module[key])
                continue
            if key not in self.module:
                self.gb_unbind(bdf=key,unbinddriver=self.real[key])
                continue
            if self.module[key] == self.real[key]:continue
            cmd = self.permit + ' modprobe ' + self.module[key]
            self.run(cmd)
            self.gb_rebind(bdf=key,unbinddriver=self.real[key],binddriver=self.module[key])

    #######################################
    # bind/rebind devices to vfio drivers
    #######################################
    def device(self):
        cmd = 'lspci -vmk '
        proc = self.run(cmd,stdout=subprocess.PIPE)
        if proc == None:exit(1)
        for i in proc.stdout.split('\n\n'):
            self.lspci = {}
            for j in i.split('\n'):
                (key,value) = j.split(':',1)
                if key.strip() in self.lspci:continue
                self.lspci[key.strip()] = value.strip()

            if 'Device' not in self.lspci:continue
            if 'Driver' in self.lspci:
                self.real[self.lspci['Device']] = self.lspci['Driver']
            if 'Module' in self.lspci:
                self.module[self.lspci['Device']] = self.lspci['Module']
        
        for key in self.wish:
            value = self.wish[key]
            if key not in self.real:
                value = value.replace('-','_')
                cmd = self.permit + ' modprobe ' + value
                self.run(cmd)
                self.gb_bind(bdf=key,binddriver=value)
                continue
            self.gb_bind(bdf=key,binddriver=value)
            if value == self.real[key]:continue
            self.match = re.search('(amd|gpu|nouveau)',self.real[key])
            if self.match != None:
                self.gb_rebind(bdf=key,unbinddriver=self.real[key],binddriver=value)
                cmd = self.permit + ' modprobe --remove ' + self.real[key]
                self.run(cmd)
                continue
            self.gb_rebind(bdf=key,unbinddriver=self.real[key],binddriver=value)
        

    def setup(self):
        for i in grp.getgrnam('kvm').gr_mem:
            if self.username == i: self.conditional = False
        if self.conditional == True:
            print('Pls add ' + self.username + ' to grp: kvm')
            exit(1)
        filepath = os.path.join(self.socksdir + self.guestname)
        if os.path.exists(filepath): 
            print(filepath + ' still in place.')
            exit(1)
        if not os.path.exists(self.virtiofsdsocksdir):
            cmd = self.permit + ' mkdir -p ' + self.virtiofsdsocksdir
            self.run(cmd)
        # oct 0o40770 is equal to int 16888
        if os.stat(self.virtiofsdsocksdir).st_mode != 16888: 
            cmd = self.permit + ' chmod 0770 ' + self.virtiofsdsocksdir
            self.run(cmd)
        if grp.getgrnam('kvm').gr_gid != os.stat(self.virtiofsdsocksdir).st_gid:
            cmd=self.permit + ' chown ' + self.username + ':kvm '+self.virtiofsdsocksdir
            self.run(cmd)
        for i in self.mountpath:
            if os.path.exists(i):continue
            print(i + 'missing')
            exit(1)
############################################
# Keep/update latest 2 snapshot only.
############################################
    def snapshot(self):
        tag = int(time.time())
        for i in self.guestimg:
            if i.find('downloads') >= 0:continue
            cmd = 'qemu-img snapshot -c ' + str(tag) + ' ' + i
            self.run(cmd)
            cmd = 'qemu-img snapshot -l ' + i
            proc = self.run(cmd,stdout=subprocess.PIPE,exit_errorcode=-1)
            if proc == None:print('failed: ' + cmd);exit(1)
            oldtag = proc.stdout.split('\n')[-3].split()[1]
            if oldtag.isdigit() == False:continue
            cmd = 'qemu-img snapshot -d ' + oldtag + ' ' + i
            self.run(cmd)

    def startvm(self):
        if self.argc < 3: self.usage(self.args[1])
        if self.argc >= 3: self.guestcfg = self.args[2]
        self.match = re.search('(qcow2|raw|img)',self.guestcfg) 
        if self.match:print('invalid config: ' + self.guestcfg);return 1 
        if os.path.exists(self.backuplock):print(self.backuplock + ' busy.');return 1
        self.configuration()
#        self.snapshot()
        self.setup()
        self.device()
        self.virtiofsd()
        self.network()
        time.sleep(1)
        self.perm()
        self.start()
        time.sleep(2)
        self.status()

    def newmac(self):
        typecode = random.randint(0,1000)%4*4+2
        oui = '0'
        result = str(self.b10t16[random.randint(0,15)])
        result += str(self.b10t16[typecode]) + ':'
        result += oui + oui + ':' + oui + oui + ':'
        result += str(self.b10t16[random.randint(0,15)])
        result += str(self.b10t16[random.randint(0,15)]) + ':'
        result += str(self.b10t16[random.randint(0,15)])
        result += str(self.b10t16[random.randint(0,15)]) + ':'
        result += str(self.b10t16[random.randint(0,15)])
        result += str(self.b10t16[random.randint(0,15)])
        self.macaddress = result

    def configuration(self):
        with open(self.guestcfg,'r') as fh:
            self.config = fh.read().split('\n')
        self.rtc = {}
        self.tap = {}
        self.guestimg = {}
        self.socketpath = {}
        self.mountpath = {}
        self.config_bridge = {}
        self.pattern = {'guestname':'^-name\s+["\']{0,1}([^"\' ]+)["\']{0,1}'}
        self.pattern['guestimg'] ='^-drive\s+file=([^"\', ]+),' 
        self.pattern['tap'] = '^-device\s+(.*)netdev=([^"\', ]+),\s*mac=([^"\' ]+)'
        self.pattern['socketpath'] = '^-chardev\s+socket,.*path=([^"\', ]+)'
        self.pattern['mountpath'] = '^-chardev\s+socket,.*path=[^\@]+([^"\', ]+).sock'
        self.pattern['wish'] = '^-device\s+([^"\', ]+),\s*host=([^"\', ]+)'
        self.pattern['rtc'] = '^-rtc\s+base=["\']{0,1}([^"\', ]+)["\']{0,1}'
        for index, l in enumerate(self.config):
            if self.pattern['guestname']:
                self.match = re.search(self.pattern['guestname'],l)
                if self.match:
                    self.guestname = self.match.group(1)
                    self.pattern['guestname'] = ''
                    continue
            self.match = re.search(self.pattern['guestimg'],l)
            if self.match:
                self.guestimg[self.match.group(1)] = self.match.group(1)
                continue
            self.match = re.search(self.pattern['tap'],l)
            if self.match:
                self.tap[self.match.group(2)] = self.match.group(3)
                self.config_bridge[self.match.group(3).replace(':','')] = \
                self.match.group(3)
                self.newmac()
                self.config[index] = '-device ' + self.match.group(1)  
                self.config[index] += 'netdev=' + self.match.group(2) 
                self.config[index] += ',mac=' + self.macaddress
                continue
            self.match = re.search(self.pattern['socketpath'],l)
            if self.match:
                self.socketpath[self.match.group(1)] = self.match.group(1)
            self.match = re.search(self.pattern['mountpath'],l)
            if self.match:
                self.mountpath[self.match.group(1).replace('@','/')] = \
                self.match.group(1).replace('@','/')
                continue
            self.match = re.search(self.pattern['wish'],l)
            if self.match:
                self.wish[self.match.group(2)] = self.match.group(1)
                continue
            self.match = re.search(self.pattern['rtc'],l)
            if self.match:
                timezone = pytz.timezone(self.match.group(1))
                self.rtc = datetime.now(timezone).strftime('%Y-%m-%dT%H:%M:%S')
                self.config[index] = '-rtc base=' + self.rtc
                continue

    def cron(self):
        for guestname in os.listdir(self.socksdir):
            self.guestcfg = os.path.join(self.gbdir + '/conf/' + guestname)
            filepath = os.path.join(self.socksdir,guestname)
            if not stat.S_ISSOCK(os.stat(filepath).st_mode):continue 
            with socket.socket(socket.AF_UNIX,socket.SOCK_STREAM) as s:
                try:
                    s.connect(filepath)
                    s.close()
                    continue
                except ConnectionRefusedError:pass
            self.configuration()
            self.redevice()
            for root,dirs,files in os.walk(self.virtiofsdsocksdir):
                for f in files:
                    self.match = re.search(self.guestname,f)
                    if not self.match:continue
                    cmd = self.permit + ' rm -f ' + os.path.join(root,f)
                    self.run(cmd)
            self.renetwork()
            cmd = self.permit + ' rm -f ' + filepath
            self.run(cmd)

    def funlock(self,funname=print):
        if not os.path.exists(self.lockfile):
            cmd = self.permit + ' touch ' + self.lockfile
            self.run(cmd)
            cmd = self.permit + ' chmod go=r ' + self.lockfile 
            self.run(cmd)
        with open(self.lockfile,'r') as self.fh:
            fcntl.flock(self.fh,fcntl.LOCK_EX | fcntl.LOCK_NB)
            funname()
            fcntl.flock(self.fh,fcntl.LOCK_UN)

    def usage(self,option=1):
        if option in self.message:
            print(self.message[option].replace("@","\n    "))
        else:
            for key in self.message:
                print(key,self.message[key].replace("@","\n    "))
        exit(1)

    def test(self):
        with tempfile.NamedTemporaryFile(mode='w+',
        dir=self.tmpdir,delete=False) as self.testfh:
            self.testfh.write('big')
        proc = self.run(cmd='cat /etc/hostname',
        stdout=subprocess.PIPE,infile=self.testfh.name)
        if proc != None:print(proc.stdout)
        self.run(cmd='date -u')

    def run(self, cmd='',infile='',outfile='',stdin=None,stdout=None,
        text=True,pass_fds=[],exit_errorcode='',shell=False):
        try:
            proc = None
            emit = __file__ + ':' + sys._getframe(1).f_code.co_name + ':' \
            + str(sys._getframe(1).f_lineno)
            if infile != '': stdin = open(infile,'r')
            if outfile != '': stdout = open(outfile,'w')
            proc = subprocess.run(cmd.split(),
            stdin=stdin,stdout=stdout,text=text,check=True,
            pass_fds=pass_fds,shell=shell)
            if infile != '': stdin.close() 
            if outfile != '': stdout.close()
            if not isinstance(proc,subprocess.CompletedProcess):
                self.debug(info='end 1',emit=emit)
                return None
            if isinstance(proc.stdout,str):
                proc.stdout = proc.stdout.rstrip('\n')
                self.debug(info='end 2',emit=emit)
                return proc
        except subprocess.CalledProcessError as e:
            emit += ':' + str(e.returncode)
            if exit_errorcode == '':
                if e.returncode != 0:
                    self.debug(info='end 3: ',emit=emit)
                    exit(1)
            elif e.returncode == exit_errorcode:
                self.debug(info='end 4',emit=emit)
                exit(1)
            return None

    def debug(self,info='',outfile='',emit=''):
        if not self.debugging: return
        emit = sys._getframe(1).f_code.co_name + ':' \
        + str(sys._getframe(1).f_lineno) + ':' + info + ':' + emit
        print(emit)

if __name__ == '__main__':
    guestbridge = Guestbridge(sys.argv)
    if guestbridge.args[1] not in guestbridge.option: guestbridge.usage()
    try:
        guestbridge.option[guestbridge.args[1]]()
    except KeyboardInterrupt:
        guestbridge.debug(info='user ctrl-C')
    finally:
        if os.path.exists(guestbridge.lockfile):
            cmd = guestbridge.permit + ' unlink ' + guestbridge.lockfile
            guestbridge.run(cmd)
        guestbridge.debug(info='session finally end')
        for key,value in guestbridge.__dict__.items():
            if isinstance(value,io.TextIOWrapper):
                value.close()
                continue
            if isinstance(value,tempfile._TemporaryFileWrapper):
                value.close() 
                if os.access(value.name,os.R_OK): os.unlink(value.name)
        if guestbridge.debugging:
            with open('/tmp/guestbridgelog','w') as guestbridge.logfh:
                print(guestbridge.__dict__,file=guestbridge.logfh)
