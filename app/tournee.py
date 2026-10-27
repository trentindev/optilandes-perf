"""Calcul d'une tournée de livraison.

Le calcul part du dépôt, visite tous les points de livraison, puis revient au
dépôt. Il se fait en deux temps :

1. une première tournée par la méthode du plus proche voisin ;
2. une amélioration par la méthode 2-opt, qui inverse des portions de la
   tournée tant que cela raccourcit la distance totale.

Ce calcul consomme beaucoup de processeur : il sert de traitement lourd dans
l'application.
"""

import math

RAYON_TERRE_KM = 6371.0
PASSES_2OPT_MAX = 6


def distance_km(a, b):
    """Distance à vol d'oiseau entre deux points (latitude, longitude), en km."""
    lat1, lon1 = math.radians(a[0]), math.radians(a[1])
    lat2, lon2 = math.radians(b[0]), math.radians(b[1])
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    h = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    return 2 * RAYON_TERRE_KM * math.asin(math.sqrt(h))


def longueur(chemin):
    return sum(distance_km(chemin[i], chemin[i + 1]) for i in range(len(chemin) - 1))


def plus_proche_voisin(depot, points):
    restants = list(points)
    chemin = [depot]
    courant = depot
    while restants:
        suivant = min(restants, key=lambda p: distance_km(courant, p))
        restants.remove(suivant)
        chemin.append(suivant)
        courant = suivant
    chemin.append(depot)
    return chemin


def ameliorer_2opt(chemin):
    meilleur = chemin
    for _ in range(PASSES_2OPT_MAX):
        ameliore = False
        for i in range(1, len(meilleur) - 2):
            for j in range(i + 1, len(meilleur) - 1):
                a, b = meilleur[i - 1], meilleur[i]
                c, d = meilleur[j], meilleur[j + 1]
                gain = (distance_km(a, b) + distance_km(c, d)) - (distance_km(a, c) + distance_km(b, d))
                if gain > 1e-9:
                    meilleur = meilleur[:i] + meilleur[i:j + 1][::-1] + meilleur[j + 1:]
                    ameliore = True
        if not ameliore:
            break
    return meilleur


def calculer_tournee(depot, points):
    """depot : (lat, lon). points : liste de (lat, lon, identifiant).

    Renvoie l'ordre de passage (identifiants) et la distance totale en km.
    """
    if not points:
        return [], 0.0
    depart = (depot[0], depot[1], None)
    chemin = ameliorer_2opt(plus_proche_voisin(depart, points))
    ordre = [p[2] for p in chemin[1:-1]]
    return ordre, round(longueur(chemin), 2)
