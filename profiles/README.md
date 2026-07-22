# Hardware profiles

Each `.conf` file uses a simple `key=value` format. No shell code is evaluated.

## Required keys

```text
profile_id=
description=
system_product=
pci_vendor_device=
pci_class=
register=
operation=
write_value=
source_note=
```

`write_mask=` is also required when `operation=masked-write`, and it must be absent or empty when `operation=write`.

## Constraints

- `system_product` must exactly match `/sys/class/dmi/id/product_name`, for example `MacPro5,1` or `iMac11,2`;
- `pci_vendor_device` is the exact PCI identifier `vvvv:dddd` in lowercase hexadecimal;
- `pci_class` is the four-digit PCI class, usually `0601` for an ISA/LPC bridge;
- `register` is a register accepted by `setpci`, for example `0xa4.b` or `0x7b.b`;
- `operation=masked-write` produces `register=value:mask`;
- `operation=write` produces `register=value`;
- a profile must only be added after documentation review and, ideally, testing on the exact hardware;
- the DMI model, PCI identifier, and PCI class must all match;
- if multiple profiles match, the installer refuses to continue.

## Masked-write example

```text
profile_id=apple-example-intel-afterg3
description=Example Apple model with Intel LPC
system_product=Example1,1
pci_vendor_device=8086:1234
pci_class=0601
register=0xa4.b
operation=masked-write
write_value=0
write_mask=1
source_note=AFTERG3_EN bit 0 verified from chipset documentation
```

## Full-write example

```text
profile_id=apple-example-nvidia-afterg3
description=Example Apple model with NVIDIA LPC
system_product=Example2,1
pci_vendor_device=10de:1234
pci_class=0601
register=0x7b.b
operation=write
write_value=0x19
source_note=Full-byte value verified for this exact controller and Apple model
```

The script strictly validates every value before building the `setpci` command. A similar commercial model name is never sufficient to reuse a profile.
