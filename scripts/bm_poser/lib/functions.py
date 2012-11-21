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

"""This script and the files it comes with are intended to automate the creation of as
many PXE booting and Network isolated nodes as you would like to test with .. 

By default it is starting a total of 4 nodes .. the original based on this xml file and 
then 3 clones of it. 

to change the number just edit the clones variable below. 

how to use:
copy this folder to your host vm (the one that is running the bootstrap vm and has the 
ooodemo bridge configured.

* make sure the base_path var is setup where you want things to be coppied.. 
* run this script bash# python ./init.py

afterwards run virsh list --all to see if the images working..."""


from settings import settings

from subprocess import call
import libvirt
import argparse
import time
import os.path
import sys
from textwrap import dedent


# TODO add code for command line **kwargs settings override

class functions(argparse.Action):
    """ david please comment this """
    # vm reference object 
    vms = {}
    settings = None
    conn = None
    xml_template = None
    
    
    def __call__(self, parser, namespace, values, option_string=None, **kwargs):
        print('%r %r %r' % (namespace, values, option_string))
        setattr(namespace, self.dest, values)
        
    
    #def __init__(self, **kwargs):
    #    """ init function """
    #    self.settings = settings
    #    
    #    # set up local qemu connection object
    #    self.conn=libvirt.open(self.settings.qemu)
    
    def create_bridge():
        """ this creates a bridge """
        
        template = dedent("""
            # bm_poser test bridge
            auto %(name)s
            iface %(name)s inet manual
                bridge_ports %(ports)s
            """)
            
        ports = " ".join(args.with_port) or "none"
        print ("Wroting new stanza for bridge interface %(name)s." % dict(name=args.name))
        
        with file(args.f, 'ab') as outf:
            outf.seek(0, 2)
            outf.write(template % dict(name=args.name, ports=ports))
        
        print ("Wrote new stanza for bridge interface %(name)s." % dict(name=args.name))
        print ("Writing dnsmasq.d exclusion file.")
        
        with file('/etc/dnsmasq.d/%(name)s' % dict(name=args.name), 'wb') as outf:
            outf.write('bind-interfaces\nexcept-interface=%(name)s\n' % dict(name=args.name))
        
        print ("Wrote dnsmasq.d exclusion file /etc/dnsmasq.d/%(name)s." % dict(name=args.name))
        
    def load_xml(self, name, image):
        """Loads the xml file and evals it with the right settings"""
        if not self.xml_template: 
            xml_template = open(self.XML_TEMPLATE_FILE, 'r').read()
        
        # ( virt_engine, arch, vm_name, memory, vcpus, image path, bridge1, bridge2 ) 
        
        return eval( xml_template_file % (self.ENGINE,self.ARCH,name,self.MAX_MEM,self.VCPU,image))
    
    def complete_test_run(self):
        """ this will run all the steps in the proper order. """
        
        # TODO
        # * Call clean up 
        
        # * Call Create
        
        # * if needed call clone
        
        # * call start 
        
    def clean_up(self):
        """ clears out vms """
        # clear out previous test nodes if they exist 
        print "Cleaning up any old VMs"
        for i in range(0,clones+1):
            try:
                dom = conn.lookupByName(base_name+str(i))
                print "Found %s, deleting it" % base_name+str(i)
                if dom.isActive():
                    dom.destroy()
                dom.undefine()
            except:
               pass
        
        # kill the qcow2 image files  
        print "Cleaning up old image files"
        cmd = "rm -rf %s/%s/*" % (base_path, node_folder)
        return_code = call(cmd, shell=True)
        
        # make a fresh copy of the empty template image for the first instance
        print "Copying empty disk image for first image"
        cmd = "cp %s/%s %s" % (base_path, template_disk, first_image)
        return_code = call(cmd, shell=True)
    
    def create(self):
        """ creates the first vm """ 
        # define the first v
        
        self.FIRST_VM_NAME = self.BASE_NAME + '0'
        image = "%s/%s/%s.qcow2" % (base_path, node_folder, first_name)
        
        
        print "Creating first VM (%s)" % first_name
        print ""
        
        xml = self.load_xml()
        
        
        conn.defineXML(xml)
        vms[first_name] = conn.lookupByName(first_name)

    def clone(self):
        """ clone x number of vms """
        if clones > 0:
            for i in range(1,clones+1):
                print "Cloning and creating another VM"
                cmd = """virt-clone --original %s --name %s --file %s""" % (
                                 first_name,
                                 base_name+str(i),
                                 base_path+node_folder+'/'+base_name+str(i)+'.qcow2')
                return_code = call(cmd, shell=True)
                vms[base_name + str(i)] = conn.lookupByName(base_name + str(i))

        print "Fixing permissions"
        cmd = 'chmod 644 %s/%s/*' % (base_path, node_folder)
        return_code = call(cmd, shell=True)
        
        cmd = 'chown libvirt-qemu %s/%s/*' % (base_path, node_folder)
        return_code = call(cmd, shell=True)

    def start(self):
        """ starts vms """ 
        # start them
        print "Starting all node(s)"
        for node_name, node in vms.iteritems():
            print "Starting node ", node_name    
            node.create()
            print "pausing ... " 
            time.sleep(start_delay)

    