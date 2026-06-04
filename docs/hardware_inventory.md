# Hardware Inventory

What hardware do I own that is part of my homelab?

## Compute
* Lenovo P620 ThinkStation
    * Nickname: machamp
    * Role: Main compute node
    * OS: Proxmox
    * CPU: AMD Threadripper 3975WX (32c/64t)
    * GPU: Nvidia RTX 3060, Nvidia Quadro P2200
    * RAM: 128GB ECC DDR4
    * Boot drive: 500GB SATA SSD
    * NVMe storage: 2x 2TB NVMe SSD

* NUC (Diglett)
    * Nickname: diglett
    * Role: Always on infra node
    * OS: Proxmox
    * CPU: i3-8109U
    * RAM: 32GB
    * Boot drive: 256GB NVME SSD
    * SSD: 1TB SATA SSD

* AOOSTAR WTR Pro
    * Nickname: alakazam
    * Role: Onsite NAS
    * OS: TrueNAS
    * CPU: Ryzen 7 5825u
    * RAM: 32GB DDR4 SODIMM
    * Boot drive: 256GB SSD
    * HDD: 4x 8TB
    * SSD: 2x 2TB SSD

* XPS 8900
    * Nickname: ditto
    * Role: Offsite backup
    * OS: TrueNAS
    * CPU: i7-6700K
    * RAM: 32GB DDR4
    * Boot drive: 256GB NVMe SSD
    * HDD: 4x 8TB
    * NVMe storage: 2x 2TB NVMe

* Custom Build (planned)
    * Nickname: tbd
    * Role: Services node
    * OS: Proxmox (planned)
    * CPU: Ryzen 7 3700x (8c/16t)
    * RAM: 128GB DDR4
    * GPU: none (P2200 is on Machamp; will migrate to this node with the services VM when built)
    * Boot drive: tbd (small SSD)
    * NVMe storage: 2TB NVMe SSD
    * Status: Not yet built

* Orange Pi Zero 3
    * Nickname: tbd
    * Role: NUT


## Networking
* Internet connection: Sonic 1g fiber
* Router: Eero
* 2.5g unmanaged switch

## Power
* UPS covers: machamp, alakazam, orange pi (orange pi must be on UPS to act as NUT server)

