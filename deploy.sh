#!/bin/bash

############################################################
#
#  Description : déploiement à la volée de conteneur docker
#
#  Auteur : Xavier, penthium2
#
#  Date : 04/09/2026 - V7.6.66
#
###########################################################

# Functions #################################_______________

spinner() {
    local i sp n
    sp='/-\|'
    n=${#sp}
    printf ' '
    while sleep 0.1; do
        printf "%s\b" "${sp:i++%n:1}"
    done
}
killspinner() {
kill $pidspin
printf "\n"
}

help() {
cat << EOF

Usage: $0 [OPTION] [ARGUMENTS]

Options :
  --create [nb] [os]   Créer des conteneurs.
                       [nb] : nombre de conteneurs (défaut: 1). Doit être un entier supérieur à 0.
                       [os] : debian ou oraclelinux (si non renseigné, le choix sera demandé).
  --baker              Construire les images Docker et déployer les conteneurs selon infra.yml.
  --drop [noms|--all]  Supprimer des conteneurs créés par le script.
                     [noms] : liste des conteneurs à supprimer (ex: $USER-test-1 $USER-apache).
                     --all : supprimer tous les conteneurs, réseaux et images du lab.
                     Sans argument : menu interactif de sélection des conteneurs.
  --stop [noms|--all]  Arrêter des conteneurs.
                       [noms] : liste des conteneurs à arrêter (ex: $USER-test-1 $USER-apache).
                       --all : arrêter tous les conteneurs du lab.
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



baker() {
    for infra_name in $(yq 'keys | .[]' infra.yml) ; do
    infra_os=$(yq  ".${infra_name}.os" infra.yml)
    infra_expports=$(yq eval '.'"${infra_name}"'.private_ports | join (" ")' infra.yml 2> /dev/null)
    if [[ -n "${infra_expports}" ]] ; then
        dockerfile="dockerfile-inline = \"FROM base_image\nEXPOSE ${infra_expports}\""
        tagports="-${infra_expports// /-}"
    else
        dockerfile='dockerfile-inline = "FROM base_image"'
        tagports=''
    fi
    dock="$dock
target \"${USER}_${infra_name}\" {
    contexts = {
        base_image = \"target:${infra_os}_base\"
    }
    $dockerfile
    tags              = [\"$USER-${infra_os}-${infra_name}${tagports}:latest\"]
}
"
    unset infra_name infra_os infra_expports
    done
    targets=$(echo "$dock" | awk -F '"' '/target / { if (targets != "") targets = targets ", "
targets = targets "\"" $2 "\""
}
END { print "[" targets "]" }')


    echo "
target \"debian_base\" {
    context    = \"./debian\"
    dockerfile = \"Dockerfile\"
}

target \"oracle_base\" {
    context    = \"./oraclelinux\"
    dockerfile = \"Dockerfile\"
}
$dock
group "default" {
    targets = $targets
}
" > docker-bake.hcl

    spinner &
    pidspin=$(jobs -p)
    disown
    if docker buildx bake > /dev/null 2>&1; then
        echo "--> Build terminé avec succès." >&2
    else
        echo "Erreur : Échec du build." >&2
        exit 1
    fi
    killspinner

}
deploylan() {
        for lan in $(yq eval '[.[].networks[]]  | unique |join (" ")' infra.yml) ; do
                if ! docker network inspect $lan > /dev/null 2>&1 ; then
                        docker network create --attachable $USER-$lan > /dev/null 2>&1
                        echo "Le réseau $lan a été créé"
                fi
        done

}

deploydock() {
        for dockerimage in $(awk -F '"' '/tags/ { print $2 }' docker-bake.hcl) ; do
                service=$(echo "$dockerimage" | sed -E 's/[a-z0-9]+-[a-z0-9]+-([a-z0-9]+)(-[0-9]+|:).*$/\1/')
                ports=$(yq eval '.'"${service}"'.public_ports | map("-p " + .) |join (" ")' infra.yml)
                container_name="$USER-$service"
                networks=$(yq eval '.'"${service}"'.networks | map("--network '"$USER-"'" + .) |join (" ")' infra.yml)
                for porthote in  $(yq eval '.'"${service}"'.public_ports[] | split(":") | .[0]' infra.yml) ; do
                        if ss -tulpn | grep ":${porthote}\b" > /dev/null 2>&1 ; then
                                printf "\033[1mLe port %s est déjà utilisé sur l'hôte. echec de la création.\033[0m\n" "$porthote"
                                dropNodes
                                return 1 >/dev/null ||exit 1
                        fi
                done
                image_tag=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -E "^$USER-.*-${service}")
                if docker run -tid --privileged \
                   -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
                   --name "$container_name" \
                   $ports \
                   $networks \
                   --cgroupns host \
                   -h "$container_name" \
                   "$image_tag" >/dev/null ; then

                    docker exec "$container_name" useradd -m -s /bin/bash "$USER"
                    docker exec "$container_name" bash -c "mkdir -p /home/$USER/.ssh && chmod 700 /home/$USER/.ssh && chown -R $USER:$USER /home/$USER/.ssh"
                    docker cp "$SSH_KEY_FILE" "$container_name:/home/$USER/.ssh/authorized_keys" > /dev/null 2>&1
                    docker exec "$container_name" bash -c "chmod 600 /home/$USER/.ssh/authorized_keys && chown $USER:$USER /home/$USER/.ssh/authorized_keys"
                    docker exec "$container_name" bash -c "echo '$USER ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/$USER"
                    docker exec "$container_name" bash -c "systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || service ssh restart 2>/dev/null"
                    echo "Conteneur $container_name créé."
                fi

        done
        infosNodes
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
            -h "$container_name" \
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

selectLabContainer() {
    local -a cases=()
    local container
    local i=1
    local containers
    local choice

    containers=$(docker ps -a -f "name=^/${USER}" --format '{{.Names}}')

    if [ -z "$containers" ]; then
        echo "Aucun conteneur du lab disponible." >&2
        return 1
    fi

    echo "Sélectionnez un conteneur du lab à supprimer :" >&2
    while read -r container; do
        cases[$i]="$container"
        echo "  $i) $container" >&2
        i=$((i+1))
    done <<< "$containers"

    read -rp "Votre choix [1-$((i-1))] (Entrée pour annuler) : " choice >&2
    case "$choice" in
        ""|0)
            echo "Annulation." >&2
            return 1
            ;;
        *)
            if [[ "$choice" =~ ^[1-9][0-9]*$ ]] && [ -n "${cases[$choice]}" ]; then
                echo "${cases[$choice]}"
            else
                echo "Erreur : Choix invalide." >&2
                return 1
            fi
            ;;
    esac
}

dropNodes() {
    if [ "$1" = "--all" ]; then
        echo "Suppression de tous les conteneurs du lab..."
        local containers
        containers=$(docker ps -a -q -f "name=^/${USER}")

        if [ -n "$containers" ]; then
            docker rm -f $containers > /dev/null
            sed -i '/172.17.0./d' "$HOME/.ssh/known_hosts" 2>/dev/null
            echo "Fin de la suppression des docks."
        else
            echo "Aucun conteneur à supprimer."
        fi
        if docker network rm $(docker network ls -q -f name=$USER*) > /dev/null 2>&1; then
            echo "Fin de la suppression des réseaux."
        fi
        if docker rmi $(docker images --format "{{.Repository}}:{{.Tag}}" | grep "^$USER-") >/dev/null 2>&1; then
            echo "Fin de la suppression des images Docker."
        fi
        return
    fi

    if [ $# -eq 0 ]; then
        echo "Aucun conteneur précisé pour --drop." >&2
    fi

    local name missing=0
    for name in "$@"; do
        if docker inspect "$name" >/dev/null 2>&1; then
            case "$name" in
                "$USER"-*)
                    if docker rm -f "$name" >/dev/null 2>&1; then
                        echo "Conteneur $name supprimé."
                    else
                        echo "Erreur : Impossible de supprimer le conteneur $name." >&2
                    fi
                    ;;
                *)
                    echo "Erreur : Le conteneur '$name' n'est pas un conteneur du lab (préfixe $USER- attendu)." >&2
                    missing=1
                    ;;
            esac
        else
            echo "Erreur : Conteneur '$name' introuvable." >&2
            missing=1
        fi
    done

    if [ $# -eq 0 ] || [ "$missing" -eq 1 ]; then
        local picked
        if picked=$(selectLabContainer); then
            docker rm -f "$picked" >/dev/null 2>&1 && echo "Conteneur $picked supprimé."
        fi
    fi
}

startNodes() {
    local containers
    containers=$(docker ps -a -q -f "name=^/${USER}")

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

stopNodes() {
    if [ "$1" = "--all" ]; then
        local containers
        containers=$(docker ps -q -f "name=^/${USER}")
        if [ -n "$containers" ]; then
            echo "Arrêt de tous les conteneurs du lab..."
            docker stop $containers
            echo "Tous les conteneurs du lab sont arrêtés."
        else
            echo "Aucun conteneur actif trouvé."
        fi
        return
    fi

    if [ $# -eq 0 ]; then
        echo "Erreur : Aucun conteneur précisé pour --stop." >&2
        help
        exit 1
    fi

    local name
    for name in "$@"; do
        if docker inspect "$name" >/dev/null 2>&1; then
            case "$name" in
                "$USER"-*)
                    if docker stop "$name" >/dev/null 2>&1; then
                        echo "Conteneur $name arrêté."
                    else
                        echo "Erreur : Impossible d'arrêter le conteneur $name." >&2
                    fi
                    ;;
                *)
                    echo "Erreur : Le conteneur '$name' n'est pas un conteneur du lab (préfixe $USER- attendu)." >&2
                    ;;
            esac
        else
            echo "Erreur : Conteneur '$name' introuvable." >&2
        fi
    done
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
    containers=$(docker ps -q -f "name=^/${USER}")

    if [ -z "$containers" ]; then
        echo "Aucun conteneur actif pour l'inventaire."
        return
    fi

    for conteneur in $containers; do
        local ip
        ip=$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{println $v.IPAddress}}{{end}}' "$conteneur" | head -n 1)
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
    containers=$(docker ps -a -q -f "name=^${USER}")

    if [ -z "$containers" ]; then
        echo "   Aucun conteneur trouvé."
        return
    fi

    for conteneur in $containers; do
        docker inspect -f '   => {{.Name}} - IP: {{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}} - Ports hôte: {{range $p, $b := .HostConfig.PortBindings}}{{range $b}}{{.HostPort}} {{end}}{{end}}' "$conteneur"
    done
    echo ""
}

# Main #####################################################

if [ $# -eq 0 ]; then
    help
    exit 0
fi

case "$1" in
    --baker)
        baker
        checkAndCreateSshKey
        deploylan
        deploydock
        ;;
    --create)
        if [ $# -gt 3 ]; then
            echo "Erreur : Trop d'arguments pour --create." >&2
            help
            exit 1
        fi
        createNodes "$2" "$3"
        ;;
    --drop)
        if [ "$2" = "--all" ]; then
            [ $# -gt 2 ] && echo "Avertissement : Arguments ignorés pour --drop --all." >&2
            dropNodes --all
        else
            shift
            dropNodes "$@"
        fi
        ;;
    --start)
        [ $# -gt 1 ] && echo "Avertissement : Arguments ignorés pour --start." >&2
        startNodes
        ;;
    --stop)
        if [ $# -eq 1 ]; then
            echo "Erreur : Merci de préciser --all ou une liste de conteneurs pour --stop." >&2
            help
            exit 1
        fi
        if [ "$2" = "--all" ]; then
            [ $# -gt 2 ] && echo "Avertissement : Arguments ignorés pour --stop --all." >&2
            stopNodes --all
        else
            shift
            stopNodes "$@"
        fi
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
