#!/bin/env -S PATH=/usr/local/bin:/usr/bin python3 -I -B
import os,sys,subprocess,time,grp,glob,datetime,re,pytz,shlex
from termcolor import colored
sys.path.append(r'/usr/local/lib/python/guestbridge/')
import device
import network
import driver
class Qemu(device.Device, network.Network, driver.Driver):
    def __init__(self,*argv):
        if hasattr(self,'qemu'):return
        device.Device.__init__(self,*argv)
        driver.Driver.__init__(self,*argv)
        network.Network.__init__(self,*argv)

    def removeallsocks(self):
        '''Prerequist: Permission required, add kvm to group e.g:vm2-sun'''
        if self.argc < 2: self.usage()
        for value in os.getgroups():
            groupname = grp.getgrgid(value).gr_name
            path = self.toolset.guesthomedir + groupname
            if not os.path.exists(path):continue
            sockspath = sorted(glob.glob(path + '/socks/' + groupname))
            if sockspath:
                self.qmp.message['question'] = self.qmp.message['status']
                if self.config.sockspath: self.config.sockspath.pop()
                self.config.sockspath.append(sockspath[0])
                self.sockssend()
                if self.qmp.message['answer'] != '"clean up"':continue
                cmd = f"{self.permit} /bin/rm -f {sockspath[0]}"
                self.run(cmd)
            roads = sorted(glob.glob(path + '/socks/' + 'serial*'))
            for sockspath in roads:
                if not os.path.exists(sockspath):continue
                cmd = f"{self.permit} /bin/rm -f {sockspath}"
                self.run(cmd)

    def snapshotrestore(self):
        '''[vm name eg:vm2-sun | image path] [snapshot ID]'''
        if self.argc < 4: self.usage()
        image = self.args[2]
        userremoveline = int(self.args[3])
        tag = ''
        grouphost = os.path.basename(image).split('-')
        if len(grouphost) < 2:
            print("invalid image name: " + self.args[2], file=sys.stderr)
            sys.exit(1)
        sockspath = self.toolset.guesthomedir + grouphost[0] + '/socks/' + grouphost[0]
        if os.path.exists(sockspath):
            print("before snapshot, shutdown | quit | remove: " + sockspath, file=sys.stderr)
            sys.exit(1)
        if not os.path.exists(image):
            image = self.toolset.guesthomedir + grouphost[0] + '/' + grouphost[1] + '.qcow2'
            if not os.path.exists(image):
                print("invalid image path: " + self.args[2], file=sys.stderr)
                sys.exit(1)
        cmd = f"/bin/qemu-img snapshot -l {image}"
        self.run(cmd,stdout=subprocess.PIPE)
        if self.proc is None:return
        removeline = userremoveline + 2
        line = self.proc.stdout.split('\n')
        if userremoveline < 0 or len(line) <= removeline:
            print("invalid snapshot Line number: " + self.args[2], file=sys.stderr)
            sys.exit(1)
        tag = re.split(r'\s+',line[removeline])[1]
        cmd = f"/bin/qemu-img snapshot -a {tag} {image}"
        self.run(cmd)

    def snapshotdelete(self):
        '''[vm name eg:vm2-sun | image path eg:vm2-data] [snapshot ID]'''
        if self.argc < 4: self.usage()
        image = self.args[2]
        userremoveline = int(self.args[3])
        tag = ''
        grouphost = os.path.basename(image).split('-')
        if len(grouphost) < 2:
            print("invalid image name: " + self.args[2], file=sys.stderr)
            sys.exit(1)
        sockspath = self.toolset.guesthomedir + grouphost[0] + '/socks/' + grouphost[0]
        if os.path.exists(sockspath):
            print("before snapshot, shutdown | quit | remove: " + sockspath, file=sys.stderr)
            sys.exit(1)
        if not os.path.exists(image):
            image = self.toolset.guesthomedir + grouphost[0] + '/' + grouphost[1] + '.qcow2'
            if not os.path.exists(image):
                print("invalid image path: " + self.args[2], file=sys.stderr)
                sys.exit(1)
        cmd = f"/bin/qemu-img snapshot -l {image}"
        self.run(cmd,stdout=subprocess.PIPE)
        if self.proc is None:return
        removeline = userremoveline + 2
        line = self.proc.stdout.split('\n')
        if len(line) <= removeline:
            print("invalid snapshot Line number: " + self.args[2], file=sys.stderr)
            sys.exit(1)
        tag = re.split(r'\s+',line[removeline])[1]
        cmd = f"/bin/qemu-img snapshot -d {tag} {image}"
        self.run(cmd)

    def snapshot(self):
        '''[vm name eg:vm2-sun | image path]'''
        if self.argc < 3: self.usage()
        image = self.args[2]
        timezone = pytz.timezone('Asia/Shanghai')
        tag = datetime.datetime.now(timezone).strftime('%Y%m%d%H%M%S')
        grouphost = os.path.basename(image).split('-')
        if len(grouphost) < 2:
            print("invalid image name: " + self.args[2], file=sys.stderr)
            sys.exit(1)
        sockspath = self.toolset.guesthomedir + grouphost[0] + '/socks/' + grouphost[0]
        if os.path.exists(sockspath):
            print("before snapshot, shutdown | quit | remove: " + sockspath, file=sys.stderr)
            sys.exit(1)
        if not os.path.exists(image):
            image = self.toolset.guesthomedir + grouphost[0] + '/' + grouphost[1] + '.qcow2'
            if not os.path.exists(image):
                print("invalid image path: " + self.args[2], file=sys.stderr)
                sys.exit(1)
        cmd = '/bin/qemu-img snapshot -c ' + tag + ' ' + image
        self.run(cmd)

    def snapshotrepo(self):
        '''.'''
        if self.argc < 2: self.usage()
        for value in os.getgroups():
            groupname = grp.getgrgid(value).gr_name
            path = self.toolset.guesthomedir + groupname
            if not os.path.exists(path):continue
            name = os.path.basename(sorted(glob.glob(path + '/*.qcow2'))[0]).split('.')[0]
            sockspath = sorted(glob.glob(path + '/socks/' + groupname))
            print('='*80)
            if not sockspath:
                print(groupname + '-' + name + ' "shutdown"')
            else:
                if self.config.sockspath: self.config.sockspath.pop()
                self.qmp.message['question'] = self.qmp.message['status']
                self.config.sockspath.append(sockspath[0])
                self.sockssend()
                print(groupname + '-' + name + ' ' + \
                colored(self.qmp.message['answer'],self.qmp.color[self.qmp.message['answer']]))

            images = sorted(glob.glob(path + '/*.qcow2'))
            for imagepath in images:
                if not imagepath: continue
                print(imagepath)
                cmd = '/bin/qemu-img snapshot -l -U ' + imagepath
                self.run(cmd,stdout=subprocess.PIPE)
                result = self.proc.stdout.split('\n')
                if self.proc is None:continue
                removeline = 2
                line = self.proc.stdout.split('\n')[removeline:]
                for i in range(len(line)):
                    vector = re.split(r'\s+',line[i])
                    vector[0] = str(i)
                    print(vector[0],vector[1],vector[4],vector[5])
        print()

    def imageinfo(self):
        '''[vm name eg:vm2-sun | image path]'''
        if self.argc < 3: self.usage()
        image = self.args[2]
        if not os.path.exists(image):
            image = image.split('-')
            if len(image) < 2:
                print("invalid: " + self.args[2], file=sys.stderr)
                sys.exit(1)
            image = self.toolset.guesthomedir + image[0] + '/' + image[1] + '.qcow2'
            if not os.path.exists(image):
                print("invalid: " + self.args[2], file=sys.stderr)
                sys.exit(1)
        cmd = '/bin/qemu-img info --backing-chain -U ' + image
        self.run(cmd)

    def serialsocksstatus(self):
        roads = sorted(glob.glob(self.config.socksdir[0] + '/' + 'serial*'))
        for path in roads:
            if not os.path.exists(path):continue
            cmd = self.permit + ' /bin/chown ' +'kvm:' + self.config.guestname[0] + ' ' + path
            self.run(cmd)
            cmd = self.permit + ' /bin/chmod ug=rw,o= ' + path
            self.run(cmd)

    def socketstatus(self):
        path = self.config.socksdir[0] + '/' + self.config.guestname[0]
        if not os.path.exists(path):
            print('missing: ' + path,file=sys.stderr)
            self.cleanup()
            sys.exit(1)
        cmd = self.permit + ' /bin/chown ' +'kvm:' + self.config.guestname[0] + ' ' + path
        self.run(cmd)
        cmd = self.permit + ' /bin/chmod ug=rw,o= ' + path
        self.run(cmd)

    def start(self):
        cmd = f"{self.permit} chmod 4755 /usr/local/bin/qemu"
        self.run(cmd)
        cmd = f"/usr/local/bin/qemu {self.config.result[0]}"
#        print(cmd)
        subprocess.Popen(shlex.split(cmd))
        cmd = f"{self.permit} chmod 0755 /usr/local/bin/qemu"
        self.run(cmd)

    def prestartvm(self):
        '''[vm name eg:vm2-sun]'''
        if self.argc < 3: self.usage()
        if len(self.args[2].split('-')) != 2:
            print('invalid: name ' + self.args[2],file=sys.stderr)
            return
        configpath = self.toolset.guesthomedir + self.args[2].split('-')[0] \
        + '/conf/' + self.args[2].split('-')[1]
        if not os.path.exists(configpath):
            print('invalid: path ' + configpath,file=sys.stderr)
            return
        self.args[2] = configpath
        self.configready()
        self.qmp.message['question'] = self.qmp.message['status']
        self.sockssend()
        if self.qmp.message['answer'] == '"running"':
            print('Guest already running ' + configpath,file=sys.stderr)
            return
        if self.qmp.message['answer'] == '"clean up"':
            cmd = f"{self.permit} /bin/rm -f {self.config.sockspath[0]}"
            self.run(cmd)
        if self.qmp.message['answer'] != '"shutdown"':
            print('Guest in unknown state ' + configpath,file=sys.stderr)
            return
        self.funlock(funname=self.startvm)

    def precleanup(self):
        '''[config file]'''
        if self.argc < 3: self.usage()
        self.funlock(funname=self.cleanup)

    def preoutput(self):
        '''[config file]'''
        if self.argc < 3: self.usage()
        self.funlock(funname=self.output)

    def output(self):
        self.bridgetap()
        time.sleep(1)
        self.binding()
        time.sleep(1)
        self.outputing()
        time.sleep(1)
        self.rebinding()
        time.sleep(1)
        self.unbridgetap()

    def startvm(self):
        self.bridgetap()
        time.sleep(1)
        self.binding()
        time.sleep(1)
        self.outputing()
        self.start()
        time.sleep(2)
        self.socketstatus()
        self.serialsocksstatus()

    def cleanup(self):
        self.rebinding()
        time.sleep(1)
        self.unbridgetap()

if __name__ == '__main__':
    target = Qemu(sys.argv)
    target.setfun()
    if target.option not in target.fun:target.usage()
    target.fun[target.option]()
