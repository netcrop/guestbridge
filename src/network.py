#!/bin/env -S PATH=/usr/local/bin:/usr/bin python3 -I -B
import sys,subprocess,re
from textwrap import dedent
sys.path.append(r'/usr/local/lib/python/guestbridge/')
import toolset
class Network(toolset.Toolset):
    def __init__(self,*argv):
        if hasattr(self,'network'):return
        toolset.Toolset.__init__(self,*argv)
        self.network = None
    
    ###########################################
    # Unbridge/Untap network
    ###########################################
    def __unbridgetap(self):
        nic = {}
        cin = {}
        cmd = f"bridge link"
        self.run(cmd,stdout=subprocess.PIPE,exit_errorcode=-1)
        for line in self.proc.stdout.split('\n'):
            if len(line) == 0:continue
            tmp = {}
            records = line.split(' ')
            for i,value in enumerate(records):
                match = re.search('master',value)
                if not match:continue
                tmp[value] = records[i+1]
            records[1] = records[1].replace(':','')
            if 'master' not in tmp:continue
            nic[records[1]] = tmp['master']
            if tmp['master'] in cin:
                cin[tmp['master']] += ' ' + records[1]
            else:
                cin[tmp['master']] = records[1]
        tmp = {}
        for value in cin.values():
            match = re.search(self.config.guestname[0],value)
            if not match:continue
            tmp = value.split(' ')
            for i,tapname in enumerate(tmp):
                if tapname not in self.config.tap:continue
                cmd = f"{self.permit} ip tuntap delete dev {tapname} mod tap"
                self.run(cmd)

    ###########################################
    # Bridge/tap network
    ###########################################
    def __bridgetap(self):
        nic = {}
        master = {}
        cmd = f"ip -o link show"
        self.run(cmd,stdout=subprocess.PIPE,exit_errorcode=-1)
        for line in self.proc.stdout.split('\n'):
            tmp = {}
            records = line.split(' ')
            for i,value in enumerate(records):
                match = re.search('(permaddr|link/ether|master)',value)
                if not match:continue
                tmp[value] = records[i+1]
            records[1] = records[1].replace(':','')
            if 'permaddr' in tmp:nic[tmp['permaddr']] = records[1]
            if 'link/ether' in tmp:nic[tmp['link/ether']] = records[1]
            if 'master' in tmp:master[records[1]] = tmp['master']
        # One physical nic belongs to only one bridge
        for key,value in nic.items():
            if not value in self.config.bridge:continue
            # Already has this bridge
            self.config.bridge.pop(value)
        # Filter out non exists physical nic from config bridge
        for key,value in self.config.bridge.items():
            if value in nic:continue
            self.config.bridge[key] = ''
        # Filter out impossible taps from config tap
#        for key,value in self.config.tap.items():
#            if value in nic:continue
#            print(value)
#            self.config.tap[key] = ''
        # Create bridges that are not already in place
        for key,value in self.config.bridge.items():
            if not value:continue
            if not value in nic:continue
            cmd = dedent(f"""\
                {self.permit} ip address flush dev {nic[value]}
                {self.permit} ip link add name {key} type bridge
                {self.permit} ip link set {key} up
                {self.permit} ip link set {nic[value]} down
                {self.permit} ip link set {nic[value]} up
                {self.permit} ip link set {nic[value]} master {key}
            """).strip()
            self.run(cmd)
        # Filter out existing taps and bridge them
        for key,value in nic.items():
            if not value in self.config.tap:continue
            # already has this tap and it's also bridged.
            if value in master:
                self.config.tap.pop(value)
                continue
            self.config.tap[value] = self.config.tap[value].replace(':','')
            cmd = f"{self.permit} ip link set dev {value} up"
            self.run(cmd)
            cmd = f"{self.permit} ip link set {value} master {self.config.tap[value]}"
            self.run(cmd)
        # Add new taps and bridge them.
        for key,value in self.config.tap.items():
            cmd = dedent(f"""\
            {self.permit} ip tuntap add dev {key} mode tap user {self.toolset.username}
            {self.permit} ip link set dev {key} up
            {self.permit} ip link set {key} master {value}
            {self.permit} sysctl -q -w net.ipv6.conf.{key}.disable_ipv6=1
            """).strip()
            self.run(cmd)
            if not key in self.config.vlan:continue
            for cmd in self.config.vlan[key].split(' '):
                cmd = f"{self.permit} {cmd.replace('-',' ')}"
                self.run(cmd)
        self.debug(self.__class__.__name__ ,debugging=self.debugging)

    def bridgetap(self):
        '''[config file]'''
        if self.argc < 3: self.usage()
        self.configready()
        self.__bridgetap()

    def unbridgetap(self):
        '''[config file]'''
        if self.argc < 3: self.usage()
        self.configready()
        self.__unbridgetap()

if __name__ == '__main__':
    target = Network(sys.argv)
    target.setfun()
    if target.option not in target.fun:target.usage(target)
    target.fun[target.option]()
