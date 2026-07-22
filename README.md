# mac-linux-auto-power-on

Utilitaire prudent pour configurer le redémarrage automatique après une panne de courant sur certains Mac Intel sous Linux avec systemd.

Le script fonctionne au minimum sur Debian et Fedora. La distribution ne détermine jamais le registre PCI : la sélection repose sur une correspondance exacte entre le modèle DMI Apple, l’identifiant du contrôleur LPC et sa classe PCI.

## Principes de sécurité

- Le mode par défaut est un diagnostic sans écriture.
- Aucun registre PCI universel n’est supposé.
- Le modèle Apple et le contrôleur LPC doivent correspondre à un profil exact.
- Un matériel inconnu provoque un refus sans écriture.
- Le bus PCI est détecté au lieu d’être codé en dur.
- L’installation réelle exige `--apply` et la confirmation textuelle `APPLY`.
- Une erreur de vérification retire le service nouvellement installé.

`setpci` écrit directement dans la configuration du chipset. Une mauvaise adresse ou un mauvais registre peut rendre la machine instable. N’ajoutez un profil qu’après vérification dans la documentation du chipset et sur le matériel concerné.

## Compatibilité actuelle

| Modèle Apple | Contrôleur LPC | PCI ID | Registre | Opération |
|---|---|---|---|---|
| `MacPro5,1` | Intel 82801JIB ICH10 | `8086:3a18` | `0xa4.b` | `0:1` |
| `iMac11,2` | Intel P55 | `8086:3b02` | `0xa4.b` | `0:1` |

Les deux profils effacent uniquement le bit 0 avec une écriture masquée :

```bash
setpci -s <fonction-pci-détectée> 0xa4.b=0:1
```

Le profil MacPro5,1 correspond au Mac Pro de Julien sous Fedora. Le profil iMac11,2 correspond à son iMac Mid-2010 sous Debian.

## Matériel documenté mais pas encore activé

Les familles suivantes nécessitent encore un profil avec modèle DMI, identifiant PCI exact et commande vérifiée avant d’être acceptées :

- Mac mini Early 2006 avec Intel ICH7-M;
- Mac mini Early 2009 avec NVIDIA MCP79;
- Mac mini Early 2010 avec NVIDIA MCP89;
- Mac mini Server 2011 avec Intel HM65;
- Mac mini MD387LL/A avec Intel Core i5-3210M.

Les profils NVIDIA peuvent nécessiter une écriture complète différente, par exemple au registre `0x7b.b`; ils ne doivent pas réutiliser automatiquement le profil Intel `0xa4.b`.

## Dépendances

### Debian, Ubuntu et dérivés

```bash
sudo apt update
sudo apt install pciutils
```

### Fedora et dérivés RPM

```bash
sudo dnf install pciutils
```

Le système doit utiliser systemd pour l’installation persistante.

## Afficher les profils

```bash
./install.sh --list-profiles
```

## Diagnostic sans modification

```bash
./install.sh
```

Le diagnostic affiche notamment :

- la distribution Linux;
- le modèle DMI;
- le profil retenu;
- la fonction PCI détectée;
- l’identifiant matériel;
- le registre et l’opération;
- la commande exacte qui serait exécutée.

Pour imposer une fonction PCI précise tout en conservant toutes les validations du profil :

```bash
./install.sh --pci-device 0000:00:1f.0
```

## Installation

```bash
sudo ./install.sh --apply
```

Le script demande ensuite de taper exactement :

```text
APPLY
```

Le service est installé ici :

```text
/etc/systemd/system/mac-auto-power-on.service
```

## Vérification

```bash
systemctl status mac-auto-power-on.service
```

Pour les deux profils actuellement inclus :

```bash
sudo setpci -v -s 0000:00:1f.0 0xa4.b
```

L’adresse PCI affichée par le diagnostic reste la source de vérité; elle ne doit pas être supposée identique sur tous les Mac.

Le test final exige une vraie perte d’alimentation alors que le Mac est allumé, suivie du retour du courant.

## Désinstallation

```bash
sudo ./uninstall.sh
```

La désinstallation retire seulement le service systemd. Elle ne force pas le registre PCI dans l’état opposé.

## Ajouter un profil

Consultez `profiles/README.md`. Le format prend en charge :

- `operation=masked-write` pour `registre=valeur:masque`;
- `operation=write` pour une écriture complète `registre=valeur`.

Un profil doit être lié à un modèle DMI et à un identifiant PCI exact. Un nom commercial voisin ou une génération similaire ne suffit pas.

## Licence

GNU GPL v3.0 ou ultérieure.
