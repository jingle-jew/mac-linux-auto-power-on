# Profils matériels

Chaque fichier `.conf` utilise un format `clé=valeur` simple. Aucun code shell n’est évalué.

## Clés obligatoires

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

`write_mask=` est également obligatoire lorsque `operation=masked-write` et doit être absent ou vide pour `operation=write`.

## Contraintes

- `system_product` doit correspondre exactement à `/sys/class/dmi/id/product_name`, par exemple `MacPro5,1` ou `iMac11,2`;
- `pci_vendor_device` est l’identifiant PCI exact `vvvv:dddd` en hexadécimal minuscule;
- `pci_class` est la classe PCI sur quatre chiffres, généralement `0601` pour un pont ISA/LPC;
- `register` est un registre accepté par `setpci`, par exemple `0xa4.b` ou `0x7b.b`;
- `operation=masked-write` produit `registre=valeur:masque`;
- `operation=write` produit `registre=valeur`;
- un profil ne doit être ajouté qu’après validation documentaire et, idéalement, essai sur le matériel exact;
- le modèle DMI, l’identifiant PCI et la classe PCI doivent tous correspondre;
- si plusieurs profils correspondent, l’installation refuse de continuer.

## Exemple d’écriture masquée

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

## Exemple d’écriture complète

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

Le script valide strictement toutes les valeurs avant de construire la commande `setpci`. Un nom commercial similaire ne suffit jamais pour réutiliser un profil.
