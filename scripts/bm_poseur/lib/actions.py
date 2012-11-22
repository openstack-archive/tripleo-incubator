#!/usr/bin/env python
#
# Copyright (c) 2012 Hewlett-Packard Development Company, L.P.
# All Rights Reserved.
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.

import libvirt
import argparse
import time
import os.path
import sys
from subprocess import call
from textwrap import dedent
import re
from lxml import objectify
from collections import defaultdict

class actions(argparse.Action):
    """ david please comment this """
    # vm reference object 
    vms = {}
    settings = None
    conn = None
    xml_template = None
                          
    def __call__(self, parser, params, values, option_string=None, **kwargs):
        """Triggered by -c command line argument """
        self.params = params
        setattr(self.params, self.dest, values)
        
        self._print(self.params, verbose=True)
        
        self.conn=libvirt.open(self.params.qemu)
        self.bridge_template = dedent(  """\
                                        
                                        # bm_poseur bridge
                                        auto %(bridge)s
                                        iface %(bridge)s inet manual
                                          bridge_ports %(ports)s 
                                        
                                        """)
        
        # action function mapping
        actions = { 'create' : self.create,
                    'get-macs' : self.get_macs,
                    'clean-up' : self.clean_up,
                    'destroy-bridge' : self.destroy_bridge,
                    'build-bridge' : self.build_bridge,
                    'start-all' : self.start_all,
                    'stop-all' : self.stop_all }
        
        if len(self.params.command) > 1:
            print "Please only use one command at a time!\n\n"
            parser.print_help()
            sys.exit(1)
        
        for command in self.params.command:
            if command in actions:
                actions[command]()
    
    
    def _print(self, output, verbose=False):
        """ print wrapper so -v and -s can be respected """
        if not self.params.silent:
            if verbose is False:
                print(output)
            elif verbose is True and self.params.verbose > 0:
                print(output)
    
    
    def get_macs(self):
        """ This returns the mac addresses  """
        output=''
        
        for domain in self.conn.listDefinedDomains():
            if not domain.find(self.params.prefix) == -1: 
                _xml = objectify.fromstring(self.conn.lookupByName(domain).XMLDesc(0))
                output += "%s," % _xml.devices.interface.mac.attrib.get("address")
          
        print '"%s"' % output.strip(',')          
                
    def destroy_bridge(self):
        """ This destroys the bridge """
        self._print("reading network config file", True)
        
        # take the bridge down 
        call('ifdown %s' % self.params.bridge, shell=True)
        
        network_file = open(self.params.network_config, 'r').read()
        ports = " ".join(self.params.bridge_port) or "none"
        to_remove = self.bridge_template % dict(bridge=self.params.bridge, ports=ports)
        to_remove = to_remove.strip().splitlines()
        
        self._print("clearing bridge", True)
        for line in to_remove: 
            network_file = network_file.replace(line,'') 
        
        self._print("writing changed network config file", True)
        outf = open( self.params.network_config , "w") 
        outf.write(network_file.strip())  
        outf.close() 
        
        self._print("removing dnsmasq exclusion file", True)
        try:
            os.remove('/etc/dnsmasq.d/%s' % self.params.bridge)
        except:
            self._print("dnsmasq exclusion missing.", True)
        
        self._print('bridge %s destroyed' % self.params.bridge )
        
    def is_already_bridge(self):
        """ returns t/f if a bridge exists or not """
        network_file = open(self.params.network_config, 'r').read()
        if network_file.find(self.params.bridge) == -1: 
            return False
        else: 
            return True
            
    
    def build_bridge(self):
        """ this creates a bridge """
        
        if not self.is_already_bridge():
            self._print("Creating bridge interface %(bridge)s." % 
                dict(bridge=self.params.bridge), verbose=True)
            
            ports = " ".join(self.params.bridge_port) or "none"
            
            self._print("   Writing new stanza for bridge interface %(bridge)s." % 
                dict(bridge=self.params.bridge), verbose=True)
            
            with file(self.params.network_config, 'ab') as outf:
                outf.seek(0, 2)
                outf.write(self.bridge_template % dict(bridge=self.params.bridge, ports=ports))
            
            self._print("  Wrote new stanza for bridge interface %s." % 
                self.params.bridge, verbose=True)
                
            self._print("   Writing dnsmasq.d exclusion file.", verbose=True)
            
            with file('/etc/dnsmasq.d/%(bridge)s' % dict(bridge=self.params.bridge), 'wb') as outf:
                outf.write('bind-interfaces\nexcept-interface=%(bridge)s\n' %
                    dict(bridge=self.params.bridge))
            
            self._print ("    Wrote dnsmasq.d exclusion file /etc/dnsmasq.d/%s." % 
                self.params.bridge, verbose=True)
                
            self._print('bring bridge online')
            call('ifup %s ' % self.params.bridge , shell=True)
        else:
            print('bridge already exists')    
    
    def load_xml(self, name, image):
        """Loads the xml file and evals it with the right settings"""
        self._print('load_xml called')
        
        if not self.xml_template: 
            template_xml = open('./lib/%s' % self.params.template_xml, 'r').read()
        
        return template_xml % dict( engine=self.params.engine,
                                    arch=self.params.arch,
                                    bridge=self.params.bridge,
                                    name=name,
                                    max_mem=self.params.max_mem,
                                    cpus=self.params.cpus,
                                    image=image )
        
        
    def clean_up(self):
        """ clears out vms """
        self._print('clean_up called')
        
        for domain in self.conn.listDefinedDomains():
            if not domain.find(self.params.prefix) == -1:                
                dom = self.conn.lookupByName(domain)
                self._print("Found %s, deleting it" % domain)
                if dom.isActive():
                    dom.destroy()
                dom.undefine()
                
        self._print("Deleting disk images from %s" % self.params.image_path)
        cmd = "rm -rf %s*" % self.params.image_path
        call(cmd, shell=True)
        
    
    def create(self):
        """ creates the first vm """
        self._print('create called') 
        
        if not os.path.isdir(self.params.image_path):
                os.makedirs(self.params.image_path)
        
        for i in range(self.params.vms):
            name = "%s%s" % (self.params.prefix , str(i))
            image = "%s%s.qcow2" % (self.params.image_path, name)
            
            
            # $IMAGE 5G
            # make a fresh copy of the empty template image for the first instance
            cmd = "kvm-img create -f qcow %s 2G" % (image)
            call(cmd, shell=True) 
        
            self.conn.defineXML(self.load_xml(name,image))
        
        self._print('Fixing permissions and ownership', verbose=True)  
        cmd = 'chmod 644 %s*' % self.params.image_path
        return_code = call(cmd, shell=True)
        
        cmd = 'chown libvirt-qemu %s*' % self.params.image_path
        return_code = call(cmd, shell=True)
        
        self._print('%s vms have been created!' % str(self.params.vms)) 
        
        
    def stop_all(self):
        """ stop_all vms TODO"""
        self._print('stop_all called')
    
    
    def start_all(self):
        """ starts vms TODO""" 
        self._print('start_all called')
        '''
        # start them
        print "Starting all node(s)"
        for node_name, node in vms.iteritems():
            print "Starting node ", node_name    
            node.create()
            print "pausing ... " 
            time.sleep(start_delay)
        '''
       

