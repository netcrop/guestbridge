#!/bin/env -S PATH=/usr/local/bin:/usr/bin python3 -I
import re,tempfile,resource,glob,io,subprocess,sys
import os,socket,getpass,random,datetime,pwd,grp,hashlib
import fcntl,stat,time,grp
class Guestbridge:
    def __init__(self,*argv):
        self.message = {'-h':' print this help message.',
        '-s':' [vm config file] ',
        '-t':' test ',
        '-b':' [bdf] [bind driver: ehci-pci/ohci-pci/xhci-hcd/vfio-pci] ',
        '-u':' [bdf] [unbind driver: ehci-pci/ohci-pci/xhci-hcd/vfio-pci] ',
        '-r':' [bdf] [unbind driver] [bind driver] : ehci-pci/ohci-pci/xhci-hcd/vfio-pci] ',
        '-c':' cron ' }
        self.argv = argv
        self.args = argv[0]
        self.argc = len(self.args)
        if self.argc == 1: self.usage()
        self.option = { '-h':self.usage,'-t':self.test,
        '-c':self.precron, '-s':self.prestartvm, '-b':self.prebind,
        '-u':self.preunbind, '-r':self.prerebind}

        self.hostname = socket.gethostname()
        self.uid = os.getuid()
        self.username = getpass.getuser()
        self.userhost = self.username + '@' + self.hostname
        self.homedir = os.environ.get('HOME') + '/'
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
        self.real = {}
        self.module = {}
        self.wish = {}
        self.bdfpattern = '(..\:..\..)'
        if self.uid != 0: self.permit = 'sudo'

    def prestartvm(self):
        self.funlock(funname=self.startvm)

    def precron(self):
        self.funlock(funname=self.cron)

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
        with open(unbindpath,'w') as fh:
            print(bdf,file=fh)
        cmd = self.permit + ' chown root ' + unbindpath
        self.run(cmd)
        cmd = 'lspci -s ' + bdf + ' -k'
        self.run(cmd)

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
        if not os.path.exists(os.path.join(self.pcidir,binddriver)):
            binddriver.replace('_','-')
        idpath = os.path.join(self.pcidir,binddriver,'new_id')
        if not os.path.exists(idpath):print('non exists: ' + idpath);exit(1)
        cmd = 'lspci -s ' + bdf + ' -n'
        proc = self.run(cmd,stdout=subprocess.PIPE)
        if proc == None:print('failed: ' + cmd );exit(1)
        id = proc.stdout.split()[2].replace(':',' ')
        cmd = self.permit + ' chown ' + self.username + ' ' + idpath
        self.run(cmd)
        with open(idpath,'w') as fh:
            print(id,file=fh)
        cmd = self.permit + ' chown root ' + idpath
        self.run(cmd)
        cmd = 'lspci -s ' + bdf + ' -k'
        self.run(cmd)
 
    #######################################
    # bind/rebind devices to vfio drivers
    #######################################
    def device(self):
        cmd = 'lspci -vmk '
        proc = self.run(cmd,stdout=subprocess.PIPE)
        if proc != None:
            self.any = proc.stdout.split('\n\n')
        for i in self.any:
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
                gb_bind(bdf=key,binddriver=value)
                continue
            self.gb_bind(bdf=key,binddriver=value)
            if value == self.real[key]:continue
            self.match = re.search('(adm|gpu|nouveau)',self.real[key])
            if self.match != None:
                print('self.gb_rebind(bdf=key,unbinddriver=self.real[key],binddriver=value)')
                cmd = self.permit + ' modprobe --remove ' + self.real[key]
                self.run(cmd)
                continue
            print('self.gb_rebind(bdf=key,unbinddriver=self.real[key],binddriver=value)')
        

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

    def snapshot(self):
        tag = int(time.time())
        for i in self.guestimg:
            cmd = 'qemu-img snapshot -c ' + str(tag) + ' ' + i
            self.run(cmd)

    def startvm(self):
        if self.argc < 3: self.usage(self.args[1])
        if self.argc >= 3: self.guestcfg = self.args[2]
        self.match = re.search('(qcow2|raw|img)',self.guestcfg) 
        if self.match:print('invalid config: ' + self.guestcfg);return 1 
        if os.path.exists(self.backuplock):print(self.backuplock + ' busy.');return 1
        self.config()
#        self.snapshot()
        self.setup()
        self.device()

    def config(self):
        with open(self.guestcfg,'r') as fh:
            lines = fh.read().split('\n')
        self.tap = {}
        self.guestimg = {}
        self.socketpath = {}
        self.mountpath = {}
        self.config_bridge = {}
        self.pattern = {'guestname':'^-name\s+["\']{0,1}([^"\' ]+)["\']{0,1}'}
        self.pattern['guestimg'] ='^-drive\s+file=([^"\', ]+),' 
        self.pattern['tap'] = '^-device\s+.*netdev=([^"\', ]+),\s*mac=([^"\' ]+)'
        self.pattern['socketpath'] = '^-chardev\s+socket,.*path=([^"\', ]+)'
        self.pattern['mountpath'] = '^-chardev\s+socket,.*path=[^\@]+([^"\', ]+).sock'
        self.pattern['wish'] = '^-device\s+([^"\', ]+),\s*host=([^"\', ]+)'
        for l in lines:
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
                self.tap[self.match.group(1)] = self.match.group(2)
                self.config_bridge[self.match.group(2).replace(':','')] = \
                self.match.group(2)
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

    def cron(self):
        for guestname in os.listdir(self.socksdir):
            answer = ''
            self.guestcfg = os.path.join(self.gbdir + '/conf/' + guestname)
            filepath = os.path.join(self.socksdir,guestname)
            if not stat.S_ISSOCK(os.stat(filepath).st_mode):continue 
            with socket.socket(socket.AF_UNIX,socket.SOCK_STREAM) as s:
                s.connect(filepath)
                s.send(b'info name')
                answer = s.recv(1024)
                s.close()
#            if answer:continue
            self.config()

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
