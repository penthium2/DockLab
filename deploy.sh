#!/bin/bash

############################################################
#
#  Description : déploiement à la volée de conteneur docker
#
#  Auteur : Xavier, penthium2
#
#  Date : 04/09/2026 - V6.6.6
#
###########################################################

# Functions #################################_______________

help() {
cat << EOF

Usage: $0 [OPTION] [ARGUMENTS]

Options :
  --create [nb] [os]   Créer des conteneurs.
                       [nb] : nombre de conteneurs (défaut: 1). Doit être un entier supérieur à 0.
                       [os] : debian ou oraclelinux (si non renseigné, le choix sera demandé).
  --drop               Supprimer tous les conteneurs créés par le script.
  --infos              Afficher l'IP et le nom des conteneurs.
  --start              Redémarrer les conteneurs arrêtés.
  --ansible            Générer l'inventaire Ansible (00_inventory.yml).

EOF
}

checkAndCreateSshKey() {
    local ssh_dir="$HOME/.ssh"
    mkdir -p "$ssh_dir" && chmod 700 "$ssh_dir"

    if [ -f "$ssh_dir/id_ed25519.pub" ]; then
        SSH_KEY_FILE="$ssh_dir/id_ed25519.pub"
    elif [ -f "$ssh_dir/id_rsa.pub" ]; then
        SSH_KEY_FILE="$ssh_dir/id_rsa.pub"
    else
        echo "--> Aucune clé SSH (id_ed25519 ou id_rsa) trouvée dans $ssh_dir." >&2
        echo "--> Génération automatique d'une clé Ed25519..." >&2
        if ssh-keygen -t ed25519 -N "" -f "$ssh_dir/id_ed25519" >/dev/null 2>&1; then
            SSH_KEY_FILE="$ssh_dir/id_ed25519.pub"
            echo "--> Clé générée avec succès : $SSH_KEY_FILE" >&2
        else
            echo "Erreur : Échec de la génération de la clé SSH." >&2
            exit 1
        fi
    fi
}

getDockerImageName() {
    local os_type=$1
    local dockerfile_path="./$os_type/Dockerfile"

    if [ ! -f "$dockerfile_path" ]; then
        echo "Erreur : Fichier $dockerfile_path introuvable." >&2
        exit 1
    fi

    local version
    version=$(awk -F ':' '/^FROM/ {print $2}' "$dockerfile_path" | head -n 1 | tr -d '\r')

    if [ -z "$version" ]; then
        echo "Erreur : Impossible de déterminer la version dans $dockerfile_path." >&2
        exit 1
    fi

    echo "${os_type}-${version}-systemd-ssh:latest"
}

checkAndBuildImage() {
    local os_type=$1
    local image_name
    image_name=$(getDockerImageName "$os_type") || exit 1

    if docker image inspect "$image_name" >/dev/null 2>&1; then
        echo "--> Image $image_name trouvée dans le registre local." >&2
    else
        echo "--> Image $image_name absente. Lancement du build..." >&2
        if ! docker build -t "$image_name" "./$os_type" >&2; then
            echo "Erreur : Échec lors du build de l'image $image_name." >&2
            exit 1
        fi
    fi

    echo "$image_name"
}

selectOS() {
    local os_input=$1

    if [ -n "$os_input" ]; then
        case "$os_input" in
            debian|oraclelinux)
                echo "$os_input"
                return
                ;;
            *)
                echo "Erreur : OS '$os_input' non géré (choix valides : debian, oraclelinux)." >&2
                exit 1
                ;;
        esac
    fi

    echo "Quel environnement souhaitez-vous utiliser ?" >&2
    echo "  1) oraclelinux (Défaut)" >&2
    echo "  2) debian" >&2
    read -rp "Votre choix [1/2] (Entrée pour par défaut) : " choice >&2

    case "$choice" in
        2|debian)
            echo "debian"
            ;;
        1|oraclelinux|"")
            echo "oraclelinux"
            ;;
        *)
            echo "Erreur : Choix invalide." >&2
            exit 1
            ;;
    esac
}

createNodes() {
    local nb_machine=$1
    local os_arg=$2

    if [ -n "$nb_machine" ]; then
        if ! [[ "$nb_machine" =~ ^[1-9][0-9]*$ ]]; then
            echo "Erreur : Le nombre de conteneurs doit être un entier supérieur à 0 (reçu : '$nb_machine')." >&2
            exit 1
        fi
    else
        nb_machine=1
    fi

    local os_type
    os_type=$(selectOS "$os_arg") || exit 1

    checkAndCreateSshKey

    local image_tag
    image_tag=$(checkAndBuildImage "$os_type")

    local idmax
    idmax=$(docker ps -a --format '{{.Names}}' | awk -F "-" -v user="$USER" '$0 ~ "^"user"-test-" {print $NF}' | sort -n | tail -1)
    idmax=${idmax:-0}

    local min=$((idmax + 1))
    local max=$((idmax + nb_machine))

    echo "--> Déploiement de $nb_machine conteneur(s) basé(s) sur $image_tag..."

    for i in $(seq $min $max); do
        local container_name="$USER-test-$i"
        
        docker run -tid --privileged \
            -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
            --name "$container_name" \
            --cgroupns host \
            -h "t$container_name" \
            "$image_tag" >/dev/null

        docker exec "$container_name" useradd -m -s /bin/bash -p sa3tHJ3/KuYvI "$USER"
        docker exec "$container_name" bash -c "mkdir -p /home/$USER/.ssh && chmod 700 /home/$USER/.ssh && chown -R $USER:$USER /home/$USER/.ssh"
        
        docker cp "$SSH_KEY_FILE" "$container_name:/home/$USER/.ssh/authorized_keys"
        docker exec "$container_name" bash -c "chmod 600 /home/$USER/.ssh/authorized_keys && chown $USER:$USER /home/$USER/.ssh/authorized_keys"
        
        docker exec "$container_name" bash -c "echo '$USER ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/$USER"
        
        docker exec "$container_name" bash -c "systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || service ssh restart 2>/dev/null"

        echo "Conteneur $container_name créé."
    done

    infosNodes  
}

dropNodes() {
    echo "Suppression des conteneurs..."
    local containers
    containers=$(docker ps -a -q -f "name=^/${USER}-test-")
    
    if [ -n "$containers" ]; then
        docker rm -f $containers
        sed -i '/172.17.0./d' "$HOME/.ssh/known_hosts" 2>/dev/null
        echo "Fin de la suppression."
    else
        echo "Aucun conteneur à supprimer."
    fi
}

startNodes() {
    local containers
    containers=$(docker ps -a -q -f "name=^/${USER}-test-")

    if [ -n "$containers" ]; then
        echo "Redémarrage des conteneurs..."
        docker start $containers
        for conteneur in $containers; do
            docker exec "$conteneur" bash -c "systemctl restart sshd 2>/dev/null || service ssh restart 2>/dev/null"
        done
        echo "Conteneurs redémarrés."
    else
        echo "Aucun conteneur trouvé."
    fi
}

createAnsible() {
    local ANSIBLE_DIR="ansible_dir"
    mkdir -p "$ANSIBLE_DIR/host_vars" "$ANSIBLE_DIR/group_vars"
    
    cat << EOF > "$ANSIBLE_DIR/00_inventory.yml"
all:
  vars:
    ansible_python_interpreter: /usr/bin/python3
    ansible_user: $USER
  hosts:
EOF

    local containers
    containers=$(docker ps -q -f "name=^/${USER}-test-")

    if [ -z "$containers" ]; then
        echo "Aucun conteneur actif pour l'inventaire."
        return
    fi

    for conteneur in $containers; do
        local ip
        ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$conteneur")
        local name
        name=$(docker inspect -f '{{.Name}}' "$conteneur" | sed 's/\///')
        
        echo "    $name:" >> "$ANSIBLE_DIR/00_inventory.yml"
        echo "      ansible_host: $ip" >> "$ANSIBLE_DIR/00_inventory.yml"
    done

    echo "Inventaire Ansible généré dans $ANSIBLE_DIR/00_inventory.yml"
}

infosNodes() {
    echo ""
    echo "Informations des conteneurs : "
    local containers
    containers=$(docker ps -a -q -f "name=^/${USER}-test-")

    if [ -z "$containers" ]; then
        echo "   Aucun conteneur trouvé."
        return
    fi

    for conteneur in $containers; do      
        docker inspect -f '   => {{.Name}} - {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$conteneur"
    done
    echo ""
}

# Main #####################################################

if [ $# -eq 0 ]; then
    help
    exit 0
fi

case "$1" in
    --create)
        if [ $# -gt 3 ]; then
            echo "Erreur : Trop d'arguments pour --create." >&2
            help
            exit 1
        fi
        createNodes "$2" "$3"
        ;;
    --drop)
        [ $# -gt 1 ] && echo "Avertissement : Arguments ignorés pour --drop." >&2
        dropNodes
        ;;
    --start)
        [ $# -gt 1 ] && echo "Avertissement : Arguments ignorés pour --start." >&2
        startNodes
        ;;
    --ansible)
        [ $# -gt 1 ] && echo "Avertissement : Arguments ignorés pour --ansible." >&2
        createAnsible
        ;;
    --infos)
        [ $# -gt 1 ] && echo "Avertissement : Arguments ignorés pour --infos." >&2
        infosNodes
        ;;
    *)
        echo "Erreur : Option '$1' non reconnue." >&2
        help
        exit 1
        ;;
esac