#!/usr/bin/env bash
# Vérifie que le poste est prêt pour le TP.
# Chaque ligne affiche OK, ATTENTION (le TP peut se faire, mais les mesures seront moins fiables)
# ou ERREUR (à corriger avant la séance).
set -uo pipefail
cd "$(dirname "$0")/.."

erreurs=0
attentions=0
ok()        { echo "OK         $*"; }
attention() { echo "ATTENTION  $*"; attentions=$((attentions + 1)); }
erreur()    { echo "ERREUR     $*"; erreurs=$((erreurs + 1)); }

IMAGES="caddy:2 postgres:16 grafana/k6:1.6.1 optilandes-app:1.0.0 optilandes-app:1.1.0"
PORT=$(grep -s '^PORT=' .env | cut -d= -f2)
PORT=${PORT:-8080}

# 1. Système
if [ "$(uname -s)" = "Linux" ]; then
    ok "Système Linux"
else
    erreur "Le TP demande une distribution Linux (Ubuntu native ou WSL2)"
fi

# 2. WSL : version et emplacement du dépôt
noyau=$(cat /proc/sys/kernel/osrelease 2>/dev/null || echo "")
if echo "$noyau" | grep -qi microsoft; then
    if echo "$noyau" | grep -qiE "wsl2|microsoft-standard"; then
        ok "WSL2 détecté"
    else
        erreur "WSL1 détecté : le TP demande WSL2 (wsl --set-version <distribution> 2 sous Windows)"
    fi
    case "$(pwd -P)" in
        /mnt/*) erreur "Dépôt situé côté Windows ($(pwd -P)) : le cloner dans le dossier personnel Linux (~)" ;;
        *)      ok "Dépôt situé dans le système de fichiers Linux" ;;
    esac
else
    ok "Linux natif détecté"
fi

# 3. Docker et Docker Compose
if ! command -v docker > /dev/null 2>&1; then
    erreur "Commande docker introuvable"
elif ! docker info > /dev/null 2>&1; then
    erreur "Docker ne répond pas sans sudo (service arrêté, utilisateur absent du groupe docker, ou intégration WSL de Docker Desktop désactivée)"
else
    ok "Docker répond ($(docker version --format '{{.Server.Version}}' 2>/dev/null))"
    if docker compose version > /dev/null 2>&1; then
        ok "Docker Compose répond ($(docker compose version --short 2>/dev/null))"
    else
        erreur "Commande « docker compose » indisponible"
    fi

    # 4. Ressources vues par Docker
    memoire_mo=$(( $(docker info --format '{{.MemTotal}}') / 1024 / 1024 ))
    if [ "$memoire_mo" -ge 3500 ]; then
        ok "Mémoire disponible pour Docker : ${memoire_mo} Mo"
    else
        attention "Mémoire disponible pour Docker : ${memoire_mo} Mo (3 500 Mo conseillés)"
    fi
    processeurs=$(docker info --format '{{.NCPU}}')
    if [ "$processeurs" -ge 4 ]; then
        ok "Processeurs disponibles pour Docker : ${processeurs}"
    else
        attention "Processeurs disponibles pour Docker : ${processeurs} (4 conseillés : k6 et l'application se partageront le processeur)"
    fi

    # 5. Images
    for image in $IMAGES; do
        if docker image inspect "$image" > /dev/null 2>&1; then
            ok "Image présente : $image"
        else
            erreur "Image absente : $image (lancer ./scripts/preparer.sh avec une connexion Internet)"
        fi
    done
fi

# 6. Espace disque
libre_mo=$(( $(df -Pk . | awk 'NR==2 {print $4}') / 1024 ))
if [ "$libre_mo" -ge 3000 ]; then
    ok "Espace disque libre : ${libre_mo} Mo"
else
    attention "Espace disque libre : ${libre_mo} Mo (3 000 Mo conseillés)"
fi

# 7. Port
if command -v ss > /dev/null 2>&1 && ss -ltn | awk '{print $4}' | grep -qE "[:.]${PORT}$"; then
    if docker compose ps --status running --services 2>/dev/null | grep -qx caddy; then
        ok "Port ${PORT} utilisé par Caddy (l'application est déjà démarrée)"
    else
        erreur "Port ${PORT} déjà utilisé : changer PORT dans le fichier .env"
    fi
else
    ok "Port ${PORT} libre"
fi

# 8. Dépôt Git : étiquettes et fins de ligne
if git rev-parse --verify --quiet v1.0.0 > /dev/null 2>&1 && git rev-parse --verify --quiet v1.1.0 > /dev/null 2>&1; then
    ok "Étiquettes v1.0.0 et v1.1.0 présentes"
else
    erreur "Étiquettes v1.0.0 et v1.1.0 absentes : cloner le dépôt complet (git clone, sans --depth)"
fi
if grep -lI $'\r' docker-compose.yml scripts/*.sh caddy/* db/init/*.sql config/*.env k6/*.js > /dev/null 2>&1; then
    erreur "Fins de ligne Windows (CRLF) détectées : cloner le dépôt depuis Linux, pas depuis Windows"
else
    ok "Fins de ligne Unix (LF)"
fi

echo
echo "Bilan : ${erreurs} erreur(s), ${attentions} point(s) d'attention."
[ "$erreurs" -eq 0 ]
