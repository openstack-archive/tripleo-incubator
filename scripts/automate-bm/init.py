"""
@author    David Lenwell 

intended use:
this script and the files it comes with are intended to automate the creation startup and 
cloning of as many nodes as you would like to test with .. 

by default it is starting a total of 4 nodes .. the original based on this xml file and 
then 3 clones of it. 

to change the number just edit the clones variable below. 

how to use:
copy this folder to your host vm (the one that is running the bootstrap vm and has the 
ooodemo bridge configured.

* make sure the base_path var is setup where you want things to be coppied.. 
* run this script bash# python ./init.py

afterwards run virsh list --all to see if the images working... 

"""

from subprocess import call
import libvirt
import time


# how many do you want to create (should be command line arg) 
clones = 3 

# some variables to make adjustments easier
base_name = 'node'
first_name = base_name + '0'
base_path = '/raid/vm/tripleo/bm-template/'
node_folder = 'nodes' 
template_disk = 'template.qcow2'
first_image = base_path+node_folder+'/'+first_name+'.qcow2'
start_delay = 10

print "connecting to local qemu"
# connect to qemu
conn=libvirt.open("qemu:///system")

# burndown first
print "burn this mother fucker down"
print ""
print ""
# clear out previous test nodes if they exist 
for i in range(0,clones+1):
    print "check for", base_name+str(i)
    print ""
    try:
        dom = conn.lookupByName(base_name+str(i))
        print "it does exist .. first destroy it "
        # remove it .. we're starting fresh 
        if dom.isActive():
            dom.destroy()
        
        print "then undefine it"
        print ""
        dom.undefine()
    except:
        """ nothing """
        print "this doesn't exist moving on "
        print ""

# kill the qcow2 image files  
print "deleting previous runs image files"
print ""
command_ = 'rm -rf ' + base_path + node_folder + '/* '
return_code = call(command_, shell=True)

# make a fresh copy of the empty template image for the first instance
print "copying in the empty disk image for first image"
print ""
command_ = 'cp ' + base_path+template_disk + ' ' + first_image
return_code = call(command_, shell=True)


# populate first vm values and write to an xml file
xml_template = """<domain type='kvm' id='4'>
  <name>%s</name>
  <memory>%s</memory>
  <vcpu>%s</vcpu>
  <os>
    <type arch='i686' machine='pc-1.0'>hvm</type>
    <boot dev='network'/>
    <boot dev='hd'/>
    <bootmenu enable='no'/>
  </os>
  <features>
    <acpi/>
    <apic/>
    <pae/>
  </features>
  <clock offset='utc'/>
  <on_poweroff>destroy</on_poweroff>
  <on_reboot>restart</on_reboot>
  <on_crash>restart</on_crash>
  <devices>
    <emulator>/usr/bin/kvm</emulator>
    <disk type='file' device='disk'>
      <driver name='qemu' type='raw'/>
      <source file='%s'/>
      <target dev='vda' bus='virtio'/>
      <alias name='virtio-disk0'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x05' function='0x0'/>
    </disk>
    <interface type='bridge'>
      <mac address='52:54:00:97:71:c3'/>
      <source bridge='ooodemo'/>
      <target dev='vnet1'/>
      <model type='virtio'/>
      <alias name='net0'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x03' function='0x0'/>
    </interface>
    <interface type='bridge'>
      <mac address='52:54:00:97:71:c4'/>
      <source bridge='ooodemo'/>
      <target dev='vnet2'/>
      <alias name='net1'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x07' function='0x0'/>
    </interface>
    <console type='pty' tty='/dev/pts/4'>
      <source path='/dev/pts/4'/>
      <target type='serial' port='0'/>
      <alias name='serial0'/>
    </console>
    <input type='mouse' bus='ps2'/>
    <graphics type='vnc' port='5901' autoport='yes'/>
    <video>
      <model type='cirrus' vram='1000' heads='1'/>
      <alias name='video0'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x0'/>
    </video>
    <memballoon model='virtio'>
      <alias name='balloon0'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x06' function='0x0'/>
    </memballoon>
  </devices>
</domain>""" % (first_name,'524000','1',first_image)


# list of id's 
vms = {}

# define the first v
print "defining first bm node called " , first_name
print ""

#print xml_template
#print ""
#print ""
#print ""


conn.defineXML(xml_template)

vms[first_name] = conn.lookupByName(first_name)

print "starting the cloning process"
# clone it x times 
for i in range(1,clones+1):
    print "starting new clone"
    print ""
    command_ = """virt-clone --original %s --name %s --file %s""" % (first_name,
                      base_name+str(i),
                      base_path+node_folder+'/'+base_name+str(i)+'.qcow2')
     
    return_code = call(command_, shell=True)
    
    # add 
    print " adding to dictionary"
    vms[base_name + str(i)] = conn.lookupByName(base_name + str(i))

print "fixing permissions"
print ""
command_ = 'chmod 644 ' + base_path + node_folder + '/* '
return_code = call(command_, shell=True)

print "fixing ownership"
print ""
command_ = 'chown libvirt-qemu ' + base_path + node_folder + '/* '
return_code = call(command_, shell=True)



# start all nodes 
print "starting nodes"


for node_name, node in vms.iteritems():
    print "starting node ", node_name    
    node.create()
    print "pausing ... " 
    time.sleep(start_delay)
""""""


