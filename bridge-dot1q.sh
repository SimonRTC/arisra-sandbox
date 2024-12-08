# This script is a OvS development draft to implement 802.1ad

# "{EXT_PORT_BRIDGE}" is the external port on bridge connected to the switch.
# "{VM_PORT_BRIDGE}" is the virtual machine port on bridge.
# "{VM2BRIDGE_TRANSIT_VLAN}" is the vlan tag used to forward traffic between the virtual machine and the internal OvS bridge (br-int).
# "{VXLAN_TRANSIT_VLAN}" is the vlan tag used to forward traffic between the host (hypervisor) and the ToR (leaf) switch using bridge (br-ext).
# "{CUSTOMER_DOT1Q_VLAN}" is the customer dot1q encapsulation vlan tag.

ovs-vsctl set port {EXT_PORT_BRIDGE} vlan_mode=dot1q-tunnel tag={CUSTOMER_DOT1Q_VLAN} cvlans={VM2BRIDGE_TRANSIT_VLAN},{VXLAN_TRANSIT_VLAN}
ovs-ofctl add-flow br-int in_port={VM_PORT_BRIDGE},dl_vlan={VM2BRIDGE_TRANSIT_VLAN},actions=mod_vlan_vid:{VXLAN_TRANSIT_VLAN},output:{EXT_PORT_BRIDGE}
ovs-ofctl add-flow br-int in_port={EXT_PORT_BRIDGE},dl_vlan={VXLAN_TRANSIT_VLAN},actions=mod_vlan_vid:{VM2BRIDGE_TRANSIT_VLAN},output:{VM_PORT_BRIDGE}

#### Mellanox (ovs-test) on GitHub (eg. https://github.com/Mellanox/ovs-tests/blob/master/test-ovs-qinq-and-vlan.sh)
ovs-vsctl add-port br-ovs $REP tag=$out_vlan vlan-mode=dot1q-tunnel other-config:qinq-ethtype=802.1q

### dot1q docs: https://developers.redhat.com/blog/2017/06/06/open-vswitch-overview-of-802-1ad-qinq-support

### Tests

# Simulates the processing of a hypothetical packet in the OpenFlow-based forwarding pipeline ("{OVS_PORT_NUMBER}" == "ens4" port number in OvS)
ovs-appctl ofproto/trace br-ext in_port={OVS_PORT_NUMBER},dl_vlan={VXLAN_TRANSIT_VLAN},dl_dst={EXAMPLE_DESTINATION_MAC}

### Bridges

# Create external bridge (br-ext) with trunk range 100-1124 (up to 1024 vxlan per host)
ovs-vsctl add-br br-ext
ovs-vsctl add-port br-ext ens4
ovs-vsctl set port ens4 vlan_mode=trunk
ovs-vsctl set port ens4 trunks=100-1124

# Create dot1q bridge (br-dot1q)
ovs-vsctl add-br br-dot1q

### VPC

# Create internal transit vlan mapping from ToR (leaf) to dot1q-tunnel bridge
ovs-vsctl add-port br-ext eth0.200 tag=200 -- set interface eth0.200 type=patch options:peer=eth1.200
ovs-vsctl add-port br-dot1q eth1.200 tag=200 -- set interface eth1.200 type=patch options:peer=eth0.200