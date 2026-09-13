#!/bin/env -S PATH=/usr/local/bin:/usr/bin python3 -I -B
import os,sys,re
from pathlib import Path
from collections import namedtuple
from collections import defaultdict
from itertools import zip_longest
sys.path.append(r'/usr/local/lib/python/guestbridge/')
import toolset
class Config(toolset.Toolset):
    def __init__(self,*argv):
        if hasattr(self,'config'):return
        toolset.Toolset.__init__(self,*argv)

    def __read_vlan(self):
        '''[vlan config file]'''
        if not Path(self.toolset.vlan_conf).is_file():
            print(self.__class__.__name__ + ': invalid: '+ self.toolset.vlan_conf)
            sys.exit(1)
        content = []
        with open(self.toolset.vlan_conf, 'r',encoding='utf-8') as fh:
            content.extend(fh.read().strip().split('\n'))
        for i in content:
            res = i.split(' ',maxsplit=1)
            self.config.vlan.update(dict(zip_longest(*[iter(res)] * 2,fillvalue="")))
#        print(self.config.vlan)

    def __read_pci(self):
        '''[pci config file]'''
        if not Path(self.toolset.pci_conf).is_file():
            print(self.__class__.__name__ + ': invalid: '+ self.toolset.pci_conf)
            sys.exit(1)
        content = []
        with open(self.toolset.pci_conf, 'r',encoding='utf-8') as fh:
            content.extend(fh.read().strip().split('\n'))
        for i in content:
            res = i.split(' ',maxsplit=1)
            self.config.pci.update(dict(zip_longest(*[iter(res)] * 2,fillvalue="")))
#        print(self.config.pci)


    def __configuration(self):
        '''[config file]'''
        if self.argc < 3: self.usage()
        self.config.guestcfg.append(self.args[2])
        if not Path(self.config.guestcfg[0]).is_file():
            print(self.__class__.__name__ + ': invalid: '+ self.config.guestcfg[0])
            sys.exit(1)
        match = re.search('(qcow2|raw|img)',self.config.guestcfg[0])
        if match:
            print(self.__class__.__name__ + ': invalid config: ' + self.config.guestcfg[0])
            sys.exit(1)
        if os.path.exists(self.toolset.backuplock):
            print(self.toolset.backuplock + ' busy.')
            sys.exit(1)
        confdir = os.path.dirname(self.config.guestcfg[0])
        repodir = os.path.dirname(confdir)
        self.config.socksdir.append(os.path.join(repodir + '/socks/'))
        with open(self.config.guestcfg[0], 'r',encoding='utf-8') as fh:
            self.config.content.extend(fh.read().strip().split('\n'))
        for i in self.config.content:
            counter = 0
            res = i.split(' ',maxsplit=1)
            key = res.pop(0)
            value = ''.join(res).split(',')
            if not key in self.config.option:
                counter = 0
                self.config.option[key][0] = [0]
            else:
                self.config.option[key][0][0] += 1
                counter = self.config.option[key][0][0]
                self.config.option[key][counter] = []
            for j in value:
                tmp = j.split('=')
                self.config.option[key][counter].append(dict(zip_longest(*[iter(tmp)] * 2,fillvalue="")))
#        print(self.config.option.items())

    def __taping(self):
        for record in self.config.option['-netdev'].values():
            tapname = ''
            brname = ''
            if not isinstance(record[0], dict):
                record.pop(0)
            for d in record:
                if 'id' in d.keys():
                    tapname = next(iter(d.values()))
                if 'br' in d.keys():
                    brname = next(iter(d.values()))
            if brname: self.config.tap[tapname] = brname
#        print(self.config.tap)

    def __guestnaming(self):
        for record in self.config.option['-name'].values():
            if not isinstance(record[0], dict):
                record.pop(0)
            self.config.guestname.append(next(iter(record[0].keys())).strip('"'))
#        print(self.config.guestname)

    def __sockspath(self):
        for record in self.config.option['-qmp'].values():
            if not isinstance(record[0], dict):
                record.pop(0)
            self.config.sockspath.append(next(iter(record[0].keys())).strip('"'))
        self.config.sockspath[0] = self.config.sockspath[0].strip('unix:')
#        print(self.config.sockspath)

    def __bridging(self):
        for record in self.config.option['-netdev'].values():
            if not isinstance(record[0], dict):
                record.pop(0)
            for d in record:
                if not 'br' in d.keys():continue
                self.config.bridge[next(iter(d.values()))] = next(iter(record[0].keys()))
#        print(self.config.bridge)

    def __devicing(self):
        for record in self.config.option['-device'].values():
            if not isinstance(record[0], dict):
                record.pop(0)
            for d in record:
                if not 'host' in d.keys():continue
                self.config.device[next(iter(d.values()))] = next(iter(record[0].keys()))
#        print(self.config.device)

    def __bdfing(self):
        for line in self.config.option['-device'].keys():
            if not isinstance(self.config.option['-device'][line][0], dict):
                self.config.option['-device'][line].pop(0)
            id = ''
            for index in range(len(self.config.option['-device'][line])):
                if not 'host' in self.config.option['-device'][line][index].keys():continue
                bdf = self.config.pci[next(iter(self.config.option['-device'][line][index].values()))]
                if not bdf:continue
                self.config.option['-device'][line][index]['host'] = bdf
                self.config.device[bdf] = next(iter(self.config.option['-device'][line][0].keys()))
#        print(self.config.device)
#        print(self.config.option['-device'])

    def outputing(self):
        '''__ no space between commas "," __'''
        res = ''
        for key, value in self.config.option.items():
            for record in value.values():
                if not isinstance(record[0], dict):
                    record.pop(0)
                res +=  key + ' '
                for d in record:
                    for k,v in d.items():
                        if v != '':
                            res +=  k + '=' + v + ','
                        else:
                            res +=  k + ','
                res = res.strip(', ')
                res += ' '
        self.config.result.append(res)
#        print(self.config.result[0])

    def configready(self):
        '''[config file]'''
        if self.argc < 3: self.usage()
        if self.config.guestcfg:return
        self.__configuration()
        self.__read_pci()
#        self.__read_vlan()
        self.__guestnaming()
        self.__sockspath()
        self.__bridging()
        self.__taping()
        self.__bdfing()
#        print(self.config.tap,self.config.bridge,self.config.guestname,self.config.device,self.config.result)

if __name__ == '__main__':
    target = Config(sys.argv)
    target.setfun()
    if target.option not in target.fun:target.usage(target)
    target.fun[target.option]()
