# This script is a OvS development draft to implement 802.1ad

# "{EXT_PORT_BRIDGE}" is the external port on bridge connected to the switch.
# "{VM_PORT_BRIDGE}" is the virtual machine port on bridge.
# "{VM2BRIDGE_TRANSIT_VLAN}" is the vlan tag used to forward traffic between the virtual machine and the internal OvS bridge (br-int).
# "{VXLAN_TRANSIT_VLAN}" is the vlan tag used to forward traffic between the host (hypervisor) and the ToR (leaf) switch using bridge (br-ext).
# "{CUSTOMER_DOT1Q_VLAN}" is the customer dot1q encapsulation vlan tag.

ovs-vsctl set port {EXT_PORT_BRIDGE} vlan_mode=dot1q-tunnel tag={CUSTOMER_DOT1Q_VLAN} cvlans={VM2BRIDGE_TRANSIT_VLAN},{VXLAN_TRANSIT_VLAN}
ovs-ofctl add-flow br-int in_port={VM_PORT_BRIDGE},dl_vlan={VM2BRIDGE_TRANSIT_VLAN},actions=mod_vlan_vid:{VXLAN_TRANSIT_VLAN},output:{EXT_PORT_BRIDGE}
ovs-ofctl add-flow br-int in_port={EXT_PORT_BRIDGE},dl_vlan={VXLAN_TRANSIT_VLAN},actions=mod_vlan_vid:{VM2BRIDGE_TRANSIT_VLAN},output:{VM_PORT_BRIDGE}

### dot1q docs: https://developers.redhat.com/blog/2017/06/06/open-vswitch-overview-of-802-1ad-qinq-support