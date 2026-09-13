#!/bin/env -S PATH=/usr/local/bin:/usr/bin python3 -I -B
import os,sys,socket,stat,grp,glob
from collections import namedtuple
from collections import defaultdict
from termcolor import colored
sys.path.append(r'/usr/local/lib/python/guestbridge/')
import toolset
class Qmp(toolset.Toolset):
    def __init__(self,*argv):
        if hasattr(self,'qmp'):return
        toolset.Toolset.__init__(self,*argv)
        socket.setdefaulttimeout(10)

    def socksconnect(self):
        if not stat.S_ISSOCK(os.stat(self.config.sockspath[0]).st_mode):return
        with socket.socket(socket.AF_UNIX,socket.SOCK_STREAM) as s:
            try:
                s.connect(self.config.sockspath[0])
                s.close()
            except ConnectionRefusedError:
                self.debug(__name__ + 'failed: socket connection.')

    def sockssend(self):
        try:
            stat.S_ISSOCK(os.stat(self.config.sockspath[0]).st_mode)
        except FileNotFoundError:
            self.qmp.message['answer'] = '"shutdown"'
            return
        with socket.socket(socket.AF_UNIX,socket.SOCK_STREAM) as s:
            try:
                s.connect(self.config.sockspath[0])
                message = self.qmp.message['cap'] + self.qmp.message['question']
                s.sendall(message.encode())
                s.recv(1024)
                s.recv(1024)
                message = s.recv(1024).decode().replace('{"return": {"status": ','').split(',',1)[0]
                self.qmp.message['answer'] = message
                s.close()
            except ConnectionRefusedError:
                self.qmp.message['answer'] = '"clean up"'
                s.close()
                return
            except TimeoutError:
                self.qmp.message['answer'] = '"clean up"'
                s.close()
                print('waiting socket ' + self.config.sockspath[0],file=sys.stderr)
                return

    def removesocks(self):
        '''[vm name eg:vm2-sun]'''
        if self.argc < 3: self.usage()
        sockspath = self.toolset.guesthomedir + self.args[2].split('-')[0] \
        + '/socks/' + self.args[2].split('-')[0]
        if not os.path.exists(sockspath):
            print('invalid: ' + sockspath,file=sys.stderr)
            return
        cmd = self.permit + ' /bin/unlink ' + sockspath
        self.run(cmd)

    def pause(self):
        '''[vm name eg:vm2-sun] [force]''' 
        if self.argc < 4: self.usage()
        if self.args[3] != 'force': print('Must type: "force"',file=sys.stderr)
        sockspath = self.toolset.guesthomedir + self.args[2].split('-')[0] \
        + '/socks/' + self.args[2].split('-')[0]
        if not os.path.exists(sockspath):
            print('invalid: ' + sockspath,file=sys.stderr)
            return
        self.config.sockspath.append(sockspath)
        self.qmp.message['question'] = self.qmp.message['stop']
        self.sockssend()

    def resume(self):
        '''[vm name eg:vm2-sun] [force]''' 
        if self.argc < 4: self.usage()
        if self.args[3] != 'force': print('Must type: "force"',file=sys.stderr)
        sockspath = self.toolset.guesthomedir + self.args[2].split('-')[0] \
        + '/socks/' + self.args[2].split('-')[0]
        if not os.path.exists(sockspath):
            print('invalid: ' + sockspath,file=sys.stderr)
            return
        self.config.sockspath.append(sockspath)
        self.qmp.message['question'] = self.qmp.message['cont']
        self.sockssend()

    def quit(self):
        '''[vm name eg:vm2-sun] [opt: force]''' 
        if self.argc < 4: self.usage()
        if self.args[3] != 'force': print('Must type: "force"',file=sys.stderr)
        sockspath = self.toolset.guesthomedir + self.args[2].split('-')[0] \
        + '/socks/' + self.args[2].split('-')[0]
        if not os.path.exists(sockspath):
            print('invalid: ' + sockspath,file=sys.stderr)
            return
        self.config.sockspath.append(sockspath)
        self.qmp.message['question'] = self.qmp.message['quit']
        self.sockssend()

    def shutdown(self):
        '''[vm name eg:vm2-sun] [force]''' 
        if self.argc < 4: self.usage()
        if self.args[3] != 'force': print('Must type: "force"',file=sys.stderr)
        sockspath = self.toolset.guesthomedir + self.args[2].split('-')[0] \
        + '/socks/' + self.args[2].split('-')[0]
        if not os.path.exists(sockspath):
            print('invalid: ' + sockspath,file=sys.stderr)
            return
        self.config.sockspath.append(sockspath)
        self.qmp.message['question'] = self.qmp.message['shutdown']
        self.sockssend()

    def brief(self):
        '''.'''
        res = {}
        for value in os.getgroups():
            try:
                grp.getgrgid(value)
            except KeyError:continue
            path = self.toolset.guesthomedir + grp.getgrgid(value).gr_name
            if not os.path.exists(path):continue
            name = os.path.basename(sorted(glob.glob(path + '/*.qcow2'))[0]).split('.')[0]
            sockspath = sorted(glob.glob(path + '/socks/' + grp.getgrgid(value).gr_name))
            if not sockspath:
                res.update({f"{grp.getgrgid(value).gr_name}-{name:10}":'"shutdown"'})
                continue
            if self.config.sockspath: self.config.sockspath.pop()
            self.config.sockspath.append(sockspath[0])
            self.qmp.message['question'] = self.qmp.message['status']
            self.sockssend()
            res.update({f"{grp.getgrgid(value).gr_name}-{name:10}":\
            colored(self.qmp.message['answer'],self.qmp.color[self.qmp.message['answer']])})
        for i in sorted(res.items()):
            print(i[0],i[1])

    def status(self):
        '''[config file]'''
        self.configready()
        self.qmp.message['question'] = self.qmp.message['status']
        self.sockssend()
        print(colored(self.qmp.message['answer'],self.qmp.color[self.qmp.message['answer']]))

if __name__ == '__main__':
    target = Qmp(sys.argv)
    target.setfun(target)
    if target.option not in target.fun:target.usage(target)
    target.fun[target.option]()
