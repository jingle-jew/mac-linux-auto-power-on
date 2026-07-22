# mac-linux-auto-power-on

A cautious utility for configuring automatic startup after a power failure on selected Intel Macs running Linux with systemd.

The script supports at least Debian and Fedora. The Linux distribution never determines the PCI register: profile selection is based on an exact match between the Apple DMI model, the LPC controller ID, and its PCI class.

## Safety principles

- The default mode is a read-only diagnostic.
- No PCI register is assumed to be universal.
- The Apple model and LPC controller must match an exact profile.
- Unknown hardware is rejected without performing any write.
- The PCI bus address is detected instead of being hard-coded.
- A real installation requires `--apply` and the exact text confirmation `APPLY`.
- If verification fails, the newly installed service is removed.

`setpci` writes directly to the chipset configuration space. An incorrect address or register may make the system unstable. Only add a profile after checking the chipset documentation and validating it on the actual hardware.

## Current compatibility

| Apple model | LPC controller | PCI ID | Register | Operation |
|---|---|---|---|---|
| `MacPro5,1` | Intel 82801JIB ICH10 | `8086:3a18` | `0xa4.b` | `0:1` |
| `iMac11,2` | Intel P55 | `8086:3b02` | `0xa4.b` | `0:1` |

Both profiles clear only bit 0 using a masked write:

```bash
setpci -s <detected-pci-function> 0xa4.b=0:1
```

The MacPro5,1 profile matches Julien's Mac Pro running Fedora. The iMac11,2 profile matches his Mid-2010 iMac running Debian.

## Documented hardware not yet enabled

The following families still require a profile with an exact DMI model, an exact PCI ID, and a verified command before they can be accepted:

- Early 2006 Mac mini with Intel ICH7-M;
- Early 2009 Mac mini with NVIDIA MCP79;
- Early 2010 Mac mini with NVIDIA MCP89;
- 2011 Mac mini Server with Intel HM65;
- Mac mini MD387LL/A with Intel Core i5-3210M.

NVIDIA profiles may require a different full-register write, for example at register `0x7b.b`; they must not automatically reuse the Intel `0xa4.b` profile.

## Dependencies

### Debian, Ubuntu, and derivatives

```bash
sudo apt update
sudo apt install pciutils
```

### Fedora and RPM-based derivatives

```bash
sudo dnf install pciutils
```

The system must use systemd for persistent installation.

## List available profiles

```bash
./install.sh --list-profiles
```

## Read-only diagnostic

```bash
./install.sh
```

The diagnostic displays, among other details:

- the Linux distribution;
- the DMI model;
- the selected profile;
- the detected PCI function;
- the hardware identifier;
- the register and operation;
- the exact command that would be executed.

To force a specific PCI function while keeping all profile validation checks enabled:

```bash
./install.sh --pci-device 0000:00:1f.0
```

## Installation

```bash
sudo ./install.sh --apply
```

The script then asks you to type exactly:

```text
APPLY
```

The service is installed at:

```text
/etc/systemd/system/mac-auto-power-on.service
```

## Verification

```bash
systemctl status mac-auto-power-on.service
```

For the two profiles currently included:

```bash
sudo setpci -v -s 0000:00:1f.0 0xa4.b
```

The PCI address shown by the diagnostic remains the source of truth; it must not be assumed to be identical on every Mac.

The final test requires a real loss of power while the Mac is running, followed by power restoration.

## Uninstallation

```bash
sudo ./uninstall.sh
```

Uninstallation removes only the systemd service. It does not force the PCI register into the opposite state.

## Adding a profile

See `profiles/README.md`. The format supports:

- `operation=masked-write` for `register=value:mask`;
- `operation=write` for a full-register write using `register=value`.

A profile must be tied to an exact DMI model and an exact PCI ID. A nearby product name or similar generation is not sufficient.

## License

GNU GPL v3.0 or later.
