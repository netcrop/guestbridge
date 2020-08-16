#!/bin/env -S PATH=/usr/local/bin:/usr/bin python3 -I
import re,tempfile,resource,glob,io,subprocess,sys
import os,socket,getpass,random,datetime,pwd,grp,hashlib
import fcntl,stat
class Guestbridge:
    def __init__(self,*argv):
        self.message = {'-h':' print this help message.',
        '-r': ' [ eg: "date -u"] Run cmd with args as random unprivileged user.',
        '-t':' test ',
        '-c':' cron ' }
        self.argv = argv
        self.args = argv[0]
        self.argc = len(self.args)
        if self.argc == 1: self.usage()
        self.option = { '-h':self.usage,'-t':self.test,
        '-c':self.precron }

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
        self.permit = ''
        if self.uid != 0: self.permit = 'sudo'

    def precron(self):
        self.funlock(funname=self.cron)

    def config(self):
        with open(self.guestcfg,'r') as fh:
            lines = fh.read().split('\n')
        self.tap = {}
        self.wish = {}
        self.socketpath = {}
        self.mountpath = {}
        self.config_bridge = {}
        self.pattern = {'guestname':'^-name\s+["\']{0,1}([^"\' ]+)["\']{0,1}'}
        self.pattern['guestimg'] ='^-drive\s+file=([^"\-\', ]+),' 
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
            if self.pattern['guestimg']:
                self.match = re.search(self.pattern['guestimg'],l)
                if self.match:
                    self.guestimg = self.match.group(1)
                    self.pattern['guestimg'] = ''
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
