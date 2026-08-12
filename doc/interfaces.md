# Interface summary

| Boundary | Count | Width | Clock |
|---|---:|---:|---:|
| 10GbE MAC RX/TX | 2 | 64 bits each | 156.25 MHz |
| Network/processing packet | 1 RX, 2 TX | 256 bits | 156.25 MHz |
| Processing/System packet | 1 RX/TX pair | 256 bits | 156.25 MHz |
| PCIe user/control | 1 | 64 bits | 125 MHz |

All packet streams use ready/valid plus byte `keep`, `sop`, and `eop`.
Network RX is treated as non-stallable in wire-speed tests. The System boundary
uses asynchronous FIFOs; all other listed packet boundaries are synchronous.
