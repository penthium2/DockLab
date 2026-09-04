# 🐳 DockLab

**DockLab** est un outil Bash léger permettant de déployer instantanément des conteneurs Docker (Debian, Oracle Linux) préconfigurés avec Systemd et SSH, prêts à servir de cibles de déploiement pour **Ansible**.

> [!WARNING]
> ### ⚠️ NE PAS UTILISER EN PRODUCTION
> 
> Ce projet est exclusivement conçu pour des **environnements de test local, de développement et d'apprentissage (labs Ansible)**.
> 
> **Raisons de sécurité :**
> - **Conteneurs privilégiés** : Les conteneurs tournent avec l'option `--privileged` et le montage `/sys/fs/cgroup` pour permettre le fonctionnement de `systemd`, ce qui contourne l'isolation standard de Docker.
> - **Sudoer sans mot de passe** : L'utilisateur créé dispose des droits `sudo` complets sans mot de passe (`NOPASSWD: ALL`).
> - **Exposition du service SSH** : Les conteneurs exécutent un serveur SSH configuré de manière permissive.
> - **Mots de passe par défaut** : Des mots de passe fixes/faibles sont attribués lors de la création des utilisateurs.
> 
> **N'utilisez jamais ce script sur un serveur exposé à Internet ou en environnement de production.**

## 🚀 Fonctionnalités

- ⚡ **Déploiement à la volée** : Instanciation rapide de nœuds de test multi-OS.
- 🔑 **Gestion SSH automatique** : Détection ou génération automatique des clés SSH (`id_ed25519` ou `id_rsa`) et injection sans mot de passe.
- 🏗️ **Build intelligent** : Détection de l'image locale et build automatique depuis le `Dockerfile` si l'image est manquante.
- ⚙️ **Support Systemd complet** : Permet de tester des rôles Ansible gérant des services (`systemctl`).
- 📝 **Générateur d'inventaire Ansible** : Création automatique d'un fichier `00_inventory.yml` prêt à l'emploi.

---

## 📂 Structure du projet

```text
DockLab/
├── debian/
│   └── Dockerfile
├── oraclelinux/
│   └── Dockerfile
├── deploy.sh
├── .gitignore
├── LICENSE
└── README.md
```

# 🛠️ Prérequis

Docker installé et configuré (avec les droits d'exécution sans sudo pour votre utilisateur).


# 📖 Aide complète du script (deploy.sh)

Voici le détail complet des options acceptées par le script :

```Plaintext
Usage: ./deploy.sh [OPTION] [ARGUMENTS]

Options :
  --create [nb] [os]   Créer des conteneurs.
                       [nb] : nombre de conteneurs (défaut: 1). Doit être un entier supérieur à 0.
                       [os] : debian ou oraclelinux (si non renseigné, le choix sera demandé).
  --drop               Supprimer tous les conteneurs créés par le script.
  --infos              Afficher l'IP et le nom des conteneurs actifs/arrêtés.
  --start              Redémarrer les conteneurs arrêtés.
  --ansible            Générer l'inventaire Ansible (00_inventory.yml).
```
# 💻 Exemples d'utilisation

Rendez d'abord le script exécutable :

```Bash
chmod +x deploy.sh
```
1. Déploiement de conteneurs (--create)
Mode interactif (le script vous demande de choisir l'OS, Oracle Linux par défaut) :

```Bash
./deploy.sh --create 2
```
Déploiement direct sur Debian :

```Bash
./deploy.sh --create 3 debian
```

Déploiement direct sur Oracle Linux :

```Bash
./deploy.sh --create 2 oraclelinux
```

2. Informations des conteneurs (--infos)
Affiche le nom et l'adresse IP attribuée à chaque conteneur créé par le script :

```Bash
./deploy.sh --infos
```

3. Génération de l'inventaire Ansible (--ansible)
Crée la structure ansible_dir/ et génère le fichier 00_inventory.yml contenant la liste des conteneurs actifs et leurs adresses IP :

```Bash
./deploy.sh --ansible
```
4. Redémarrage des conteneurs (--start)
Redémarre l'ensemble des conteneurs arrêtés et relance le service SSH à l'intérieur :

```Bash
./deploy.sh --start
```
5. Suppression des conteneurs (--drop)
Supprime tous les conteneurs du lab et nettoie le fichier ~/.ssh/known_hosts des clés obsolètes :

```Bash
./deploy.sh --drop
```

# 🙏 Crédits & Remerciements

Ce projet s'inspire des travaux et formations DevOps proposés par Xavki :

- 🐙 **GitHub** : [priximmo](https://github.com/priximmo)
- 📺 **Chaîne YouTube** : [Xavki - Linux & DevOps](https://www.youtube.com/c/xavki-linux)

# 📜 Licence

Ce projet est sous licence WTFPL. Voir le fichier LICENSE pour plus de détails.
