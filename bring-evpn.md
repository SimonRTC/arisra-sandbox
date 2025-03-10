# Bring EVPN L2VPN to a local service (VM, container, managed service)

The purpose of this topology is to support 4064 vlans per overlays (VNI). We are going to use :
- Protocols
    - VXLAN
    - 802.1q
    - 802.1ad (QinQ)
    - BGP (L2VPN family)
- Softwares
    - Open vSwitch
    - FRRouting

This configuration assumes you already have a functional local environment with your existing service flooding traffic on a bridge named "br-int". Each virtual network (/or/ overlay) is flooded on a dedicated "local" 802.1q vlan on this bridge (like the OpenStack OvS driver for example).

## FRRouting

### Local EVPN configurations

```ini
frr defaults traditional
hostname hypervisor
log syslog informational
service integrated-vtysh-config
!
router bgp 65000
 bgp router-id <HYPERVISOR_IP>
 no bgp default ipv4-unicast
!
# Define the peer group for eBGP to fabric switches
 neighbor fabric peer-group
 neighbor fabric remote-as 65000
 neighbor fabric update-source <HYPERVISOR_IP>
!
# Peering with EVPN Fabric (Spine/Leaf Switches)
 neighbor <LEAF1_IP> peer-group fabric
 neighbor <LEAF2_IP> peer-group fabric
!
# Enable EVPN for L2VPN Services
 address-family l2vpn evpn
  neighbor fabric activate
  advertise-all-vni
 exit-address-family
!
# VLAN to VXLAN Mappings (VLAN-based RD Isolation)
!
vlan 100
 vni 10000
 rd <HYPERVISOR_IP>:100
 route-target import 65000:100
 route-target export 65000:100
!
vlan 200
 vni 20000
 rd <HYPERVISOR_IP>:200
 route-target import 65000:200
 route-target export 65000:200
!
vlan 300
 vni 30000
 rd <HYPERVISOR_IP>:300
 route-target import 65000:300
 route-target export 65000:300
!
```

sources:
- [ovs-discuss] VXLAN - MAC address learning/propagation through EVPN/FRsR ([mail.openvswitch.org](https://mail.openvswitch.org/))
- [ovs-discuss] BGP EVPN support ([mail.openvswitch.org](https://mail.openvswitch.org/))
- VXLAN: BGP EVPN with FRR [vincent.bernat.ch](https://vincent.bernat.ch/en/blog/2017-vxlan-bgp-evpn)

## Open vSwitch

### Setup the `br-vxlan`

```bash
# Create br-vxlan
ovs-vsctl add-br br-vxlan

# Create patch ports to connect br-int and br-vxlan
ovs-vsctl add-port br-int patch-to-vxlan \
    -- set interface patch-to-vxlan type=patch options:peer=patch-to-int

ovs-vsctl add-port br-vxlan patch-to-int \
    -- set interface patch-to-int type=patch options:peer=patch-to-vxlan

# Define the local VTEP interface
ovs-vsctl add-port br-vxlan vxlan0 \
    -- set interface vxlan0 type=vxlan \
    options:local_ip=<HYPERVISOR_IP> \
    options:remote_ip=flow \
    options:key=flow \
    options:dst_port=4789
```

### Recap of How This Works

- Incoming traffic (VXLAN → OVS):
    - Matches on VNI and QinQ VLAN 1234.
    - Removes S-VLAN (pop_vlan).
    - Pushes C-VLAN for local processing.
    - Forwards normally.

- Outgoing traffic (OVS → VXLAN):
    - Matches on C-VLAN.
    - Pushes S-VLAN 1234 for QinQ.
    - Encapsulates into VXLAN.
    - Sends to remote VTEP.

### Local flows

```bash
# VLAN 100 → VNI 10000 → QinQ VLAN 1234

# Input Flows (VXLAN to br-vxlan)
ovs-ofctl -O OpenFlow14 add-flow br-vxlan "priority=500,in_port=vxlan0,tun_id=10000,dl_type=0x88a8,dl_vlan=1234,actions=pop_vlan,push_vlan:0x8100,set_vlan_vid:100,NORMAL"
ovs-ofctl -O OpenFlow14 add-flow br-vxlan "priority=100,in_port=vxlan0,tun_id=10000,actions=drop"

# Output Flows (br-int to VXLAN)
ovs-ofctl -O OpenFlow14 add-flow br-vxlan "priority=500,dl_vlan=100,actions=push_vlan:0x88a8,set_vlan_vid=1234,set_field:10000->tun_id,output:vxlan0"


# VLAN 200 → VNI 20000 → QinQ VLAN 1234

# Input Flows
ovs-ofctl -O OpenFlow14 add-flow br-vxlan "priority=500,in_port=vxlan0,tun_id=20000,dl_type=0x88a8,dl_vlan=1234,actions=pop_vlan,push_vlan:0x8100,set_vlan_vid:200,NORMAL"
ovs-ofctl -O OpenFlow14 add-flow br-vxlan "priority=100,in_port=vxlan0,tun_id=20000,actions=drop"

# Output Flows
ovs-ofctl -O OpenFlow14 add-flow br-vxlan "priority=500,dl_vlan=200,actions=push_vlan:0x88a8,set_vlan_vid=1234,set_field:20000->tun_id,output:vxlan0"


# VLAN 300 → VNI 30000 → QinQ VLAN 1234

# Input Flows
ovs-ofctl -O OpenFlow14 add-flow br-vxlan "priority=500,in_port=vxlan0,tun_id=30000,dl_type=0x88a8,dl_vlan=1234,actions=pop_vlan,push_vlan:0x8100,set_vlan_vid:300,NORMAL"
ovs-ofctl -O OpenFlow14 add-flow br-vxlan "priority=100,in_port=vxlan0,tun_id=30000,actions=drop"

# Output Flows
ovs-ofctl -O OpenFlow14 add-flow br-vxlan "priority=500,dl_vlan=300,actions=push_vlan:0x88a8,set_vlan_vid=1234,set_field:30000->tun_id,output:vxlan0"
```