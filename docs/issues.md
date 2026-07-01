# Known Issues

---

## Tailscale subnet route breaks LAN connectivity on personal devices

**Symptom**: When a personal device (laptop) joins the Headscale tailnet with
`--accept-routes`, diglett-dns advertises `192.168.0.0/24` as a subnet route.
While the device is physically on the LAN, traffic to `192.168.0.x` addresses
is routed via the Tailscale tunnel instead of the local NIC. Because the
destination receives the packet on its LAN NIC and replies via the LAN, the
connection is asymmetric and never completes — the device becomes unreachable
from the LAN.

**Affected**: personal devices (laptops) that use `--accept-routes` on the LAN.
VMs are not affected because they use `--accept-routes=false`.

**Workaround**: On the personal device while on LAN, either:
- Disconnect from Tailscale, or
- Re-enroll with `tailscale up --accept-routes=false` while on LAN, then
  switch back to `--accept-routes` when remote

**Root cause**: `192.168.0.0/24` is advertised by diglett-dns as a Headscale
subnet route (for remote access to LAN services). Accepting this route on a
device that is already on that subnet causes a routing conflict.

**Potential fixes**:
1. Don't advertise `192.168.0.0/24` on Headscale at all — instead rely on
   Tailscale MagicDNS and per-service Tailscale IPs for remote access. Requires
   migrating `.wsh` service routing away from the subnet route model.
2. Use Tailscale's `--exit-node-allow-lan-access` flag (only helps when using
   an exit node, not for plain subnet routes).
3. Accept that `--accept-routes` is a remote-only setting and document the
   toggle as part of the on/off-LAN workflow.
