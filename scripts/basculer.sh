#!/usr/bin/env bash
# Bascule le trafic vers l'environnement bleu ou vert, sans interruption.
# Usage : ./scripts/basculer.sh bleu
#         ./scripts/basculer.sh vert
set -euo pipefail
cd "$(dirname "$0")/.."

cible="${1:-}"
case "$cible" in
    bleu) ancien="vert" ;;
    vert) ancien="bleu" ;;
    *) echo "Usage : $0 bleu|vert"; exit 1 ;;
esac

# 1. La cible doit avoir au moins une instance démarrée et en bonne santé.
saines=$(docker ps --filter "name=optilandes-app-${cible}-" --filter "health=healthy" --quiet | wc -l)
if [ "$saines" -eq 0 ]; then
    echo "ERREUR : aucune instance ${cible} en bonne santé. Bascule annulée."
    echo "Démarrer d'abord l'environnement ${cible} et attendre l'état « healthy » (docker compose ps)."
    exit 1
fi
echo "${saines} instance(s) ${cible} en bonne santé."

# 2. Réécriture de la configuration active de Caddy.
sed "s/COULEUR/${cible}/g" caddy/actif.modele > caddy/actif.caddy

# 3. Rechargement de Caddy : les requêtes en cours se terminent, les nouvelles vont vers la cible.
docker compose exec -T caddy caddy reload --config /etc/caddy/Caddyfile
echo "Trafic basculé vers ${cible}."
echo
echo "Laisser les requêtes en cours sur ${ancien} se terminer (30 s au minimum) avant de l'arrêter :"
if [ "$ancien" = "vert" ]; then
    echo "  docker compose --profile vert stop app-vert"
else
    echo "  docker compose stop app-bleu"
fi
