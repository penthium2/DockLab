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
- ⚡ **Déploiement  planifié** : Instanciation via fichier d'infrastructure infra.yml
- 🏗️ **Build intelligent** : Détection de l'image locale et build automatique depuis le `Dockerfile` si l'image est manquante ou via buildx bake.
- 🔑 **Gestion SSH automatique** : Détection ou génération automatique des clés SSH (`id_ed25519` ou `id_rsa`) et injection sans mot de passe.
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
├── infra.yml
├── LICENSE
└── README.md
```

# 🛠️ Prérequis

- Docker installé et configuré (avec les droits d'exécution sans sudo pour votre utilisateur).
- yq installé (version https://github.com/mikefarah/yq/ version v4.53.3).


# 📖 Aide complète du script (deploy.sh)

Voici le détail complet des options acceptées par le script :

```Plaintext
Usage: ./deploy.sh [OPTION] [ARGUMENTS]

Options :
  --baker              Construire les images Docker et déployer les conteneurs selon infra.yml.
  --create [nb] [os]   Créer des conteneurs.
                       [nb] : nombre de conteneurs (défaut: 1). Doit être un entier supérieur à 0.
                       [os] : debian ou oraclelinux (si non renseigné, le choix sera demandé).
  --drop [noms|--all]  Supprimer des conteneurs créés par le script.
                      [noms] : liste des conteneurs à supprimer (ex: user-test-1 user-apache).
                      --all : supprimer tous les conteneurs, réseaux et images du lab.
                      Sans argument : menu interactif de sélection des conteneurs.
  --stop [noms|--all]  Arrêter des conteneurs.
                       [noms] : liste des conteneurs à arrêter (ex: user-test-1 user-apache).
                       --all : arrêter tous les conteneurs du lab.
  --infos              Afficher l'IP et le nom des conteneurs actifs/arrêtés.
  --start              Redémarrer les conteneurs arrêtés.
  --ansible            Générer l'inventaire Ansible (00_inventory.yml).
```


# 💻 Exemples d'utilisation

Rendez d'abord le script exécutable :

```Bash
chmod +x deploy.sh
```
## Deploiement de conteneurs
1. Déploiement de conteneur (--baker)
Cette option s'appuis sur un fichier infra.yml avec les informations souhaité :
exemple de fichier infra.yml :
```
apache:
  os: "debian"
  public_ports:
    - 80:80
    - 9443:443
  networks:
    - front
    - db
mysql:
  os: "oracle"
  private_ports:
    - 3306
  networks:
    - db
```

exemple d'utilisation : 
```
./deploy.sh --baker 
 --> Build terminé avec succès.

Le réseau front a été créé
Le réseau db a été créé
Conteneur penthium2-apache créé.
Conteneur penthium2-mysql créé.

Informations des conteneurs : 
   => /penthium2-mysql - IP: 172.22.0.3  - Ports hôte: 
   => /penthium2-apache - IP: 172.22.0.2 172.21.0.2  - Ports hôte: 80 9443
```


2. Déploiement de conteneurs (--create)
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
## Commandes utiles

1. Informations des conteneurs (--infos)
Affiche le nom et l'adresse IP attribuée à chaque conteneur créé par le script :

```Bash
./deploy.sh --infos
```

2. Génération de l'inventaire Ansible (--ansible)
Crée la structure ansible_dir/ et génère le fichier 00_inventory.yml contenant la liste des conteneurs actifs et leurs adresses IP :

```Bash
./deploy.sh --ansible
```
3. Arrêt de conteneurs (--stop)
Arrête un ou plusieurs conteneurs précisés par leurs noms :

```Bash
./deploy.sh --stop penthium2-test-1 penthium2-apache
```

Les noms disponibles se retrouvent via `./deploy.sh --infos`. Pour arrêter tous les conteneurs du lab :

```Bash
./deploy.sh --stop --all
```

4. Redémarrage des conteneurs (--start)
Redémarre l'ensemble des conteneurs arrêtés et relance le service SSH à l'intérieur :

```Bash
./deploy.sh --start
```
5. Suppression des conteneurs (--drop)
Supprime un ou plusieurs conteneurs précisés par leurs noms :

```Bash
./deploy.sh --drop penthium2-test-1 penthium2-apache
```

Sans argument, un menu interactif liste les conteneurs du lab parmi lesquels choisir (un nom introuvable déclenche aussi ce menu) :

```Bash
./deploy.sh --drop
```

Pour supprimer tous les conteneurs du lab, les réseaux et les images sans confirmation, et nettoyer le fichier ~/.ssh/known_hosts des clés obsolètes :

```Bash
./deploy.sh --drop --all
```

# 🙏 Crédits & Remerciements

Ce projet s'inspire des travaux et formations DevOps proposés par Xavki :

- 🐙 **GitHub** : [priximmo](https://github.com/priximmo)
- 📺 **Chaîne YouTube** : [Xavki - Linux & DevOps](https://www.youtube.com/c/xavki-linux)

# 📜 Licence

Ce projet est sous licence WTFPL. Voir le fichier LICENSE pour plus de détails.
