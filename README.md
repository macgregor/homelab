# Homelab

This is all a WIP, once I run out of things to play with I will write clean up the documentation and make some pretty diagrams.

## Hardware

| Product | Quantity | Price | Description |
| ------- | -------- | ----- | ----------- |
| [Synology DS720+](https://www.synology.com/en-us/products/DS720+) | 1 | $399.99 | 2 disk NAS with capability to expand to 7 disks with the [DX517](https://www.synology.com/en-us/products/DX517). The DS220+ is cheaper, but has a slower CPU and no ability to expand. |
| [Seagate IronWolf 8TB NAS HDD](https://www.seagate.com/products/nas-drives/ironwolf-hard-drive/) | 2 | $159.00 | Good HDDs, not much to say. |
| [NETGEAR Nighthawk R7000 Router](https://www.netgear.com/home/wifi/routers/r7000/) | 1 | $163.21 | Already had this router, but including it anyway |
| [NETGEAR GS305EP PoE Switch](https://www.netgear.com/support/product/gs305ep.aspx) | 1 | $79.99 | To power and supply internet to 4 Raspberry Pis. |
| [Raspberry Pi 4B (1GB RAM)](https://www.raspberrypi.com/products/raspberry-pi-4-model-b/) | 1 | $49.99 | Had laying around |
| [Raspberry Pi 4B (8GB RAM)](https://www.raspberrypi.com/products/raspberry-pi-4-model-b/) | 1 | $99.99 | Had laying around |
| [Raspberry Pi POE+ HAT](https://www.raspberrypi.com/products/poe-plus-hat/) | 2 | $37.99 | The RPis require some additional hardware so the PoE doesnt burn them out. |
| [UCTRONICS 4 Bay Raspberry Pi Cluster Enclosure](https://www.amazon.com/gp/product/B09JNHKL2N/ref=ppx_od_dt_b_asin_title_s00?ie=UTF8&psc=1) | 1 | $69.99 | I planned on a 4 Pi cluster, so further scalability wasnt a concern. |
| [UCTRONICS Fan Adapter Board for Raspberry Pi Upgraded Complete Enclosure](https://www.amazon.com/dp/B09TP9HT3C?psc=1&ref=ppx_yo2ov_dt_b_product_details) | 1 | $5.99 | The PoE HAT blocks pin access to power the fans in the case so if you want to use them you need this little dongle. |
| Micro Center 32GB Micro SD Card (5 pack) | 1 | $20.69 | Primary storage for RPis. |
| Cat 6 Ethernet Cable 1 ft (10 pack) | 1 | $16.99 | Most any PoE compliant cable will do |

**Network - FreshTomato and Dynamic DNS**
Setting up a network is tough. I'm no expert, but I can fumble my way around to make something work. I already had my fancy router on hand, flashed with AdvancedTomato. Turns out that went out of support not long after I installed it. Fortunately, the FOSS community kept it going with [FreshTomato](https://www.freshtomato.org/) and I had an up to date router a few minutes later. FreshTomato is in the same vein as DD-WRT: a linux based router firmware that can bring some advanced networking features to your home router. Create VLANs for security, host a VPN server, make youre route a VPN client so all the devices on your network are also on the VPN, attach USB storage to make a simple NAS and so on. People generally buy a router known to be very compatible and the R7000 was a popular choice when I did this.


Im not sure if its necessary, but in order to get my Pi's connected to the switch visible to devices connected to my router, I needed to enable the [802.1Q VLAN](https://networklessons.com/switching/802-1q-encapsulation-explained) in the switch so it could join the default VLAN1 on the router (it can also support multiple VLANs but that gets more complicated). This means you need to look for a managed network switch and make sure your router supports 802.1Q. It may be possible to make it work without this, again I am not a network expert, but this is what I had to do with my hardware.

**Storage - Synology NAS**
Don't skimp on the thing meant to keep your data safe. Synology is expensive because they are the standard by which all other NAS are measured. One of the big selling points is [Synology Hybrid RAID (SHR)](https://kb.synology.com/en-uk/DSM/tutorial/What_is_Synology_Hybrid_RAID_SHR) which is much more flexible than standard RAID when it comes to scaling drives.

It also is itself a capable server and has many [add on packages](https://www.synology.com/en-us/dsm/packages) such as Plex, Docker, databases, http web servers and more. In fact, a Synology NAS alone would probably be enough to support a home media server and any personal projects you might have. That said, it is still a NAS and it will be hard/impossible (and prohibitively expensive) to scale compute resources. Thats where the cheap Raspberry Pis shine.

**Compute - Raspberry Pi 4B**
Raspberry Pis are small, generally cheap, complete computers based on ARM (mobile) cpus. This makes them good candidates for scalable, stateless, server clusters. Unfortunately the world is currently experiencing supply chain issues and chip shortages. This means that an 8gb RPi 4B that should be ~$100 is closter to $250, if you can even find one. So for now I am using a 1 GB and 8 GB model I bought some time ago. Once supply stabilizes I can scale up to four 8GB models.
