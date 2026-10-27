// Parcours utilisateur commun aux scénarios k6.
// Répartition des requêtes :
//   60 % consultation des créneaux libres (14 prochains jours)
//   15 % prise de rendez-vous (14 prochains jours)
//   15 % liste des livraisons (2 prochains jours)
//   10 % calcul d'une tournée (2 prochains jours)
import http from 'k6/http';
import { check } from 'k6';

export const CIBLE = __ENV.CIBLE || 'http://caddy';

// Engagements du SLA, modifiables au lancement :
//   SLA_MS        temps de réponse maximal du 95e centile, en millisecondes
//   ERREURS_MAX   part maximale de requêtes en erreur (0.005 = 0,5 %)
const SLA_MS = parseInt(__ENV.SLA_MS || '2000', 10);
const ERREURS_MAX = parseFloat(__ENV.ERREURS_MAX || '0.005');

export const SEUILS = {
  http_req_duration: [`p(95)<${SLA_MS}`],
  http_req_failed: [`rate<${ERREURS_MAX}`],
  'http_req_duration{nom:creneaux}': [`p(95)<${SLA_MS}`],
  'http_req_duration{nom:rendez-vous}': [`p(95)<${SLA_MS}`],
  'http_req_duration{nom:livraisons}': [`p(95)<${SLA_MS}`],
  'http_req_duration{nom:tournees}': [`p(95)<${SLA_MS}`],
};

// Premier jour des données : 2 novembre 2026 (les mois sont numérotés à partir de 0).
const PREMIER_JOUR = Date.UTC(2026, 10, 2);

function dateDans(jours) {
  return new Date(PREMIER_JOUR + jours * 86400000).toISOString().slice(0, 10);
}

function entier(min, max) {
  return min + Math.floor(Math.random() * (max - min + 1));
}

export function parcoursUtilisateur() {
  const zone = entier(1, 24);
  const tirage = Math.random();
  let reponse;

  if (tirage < 0.60) {
    reponse = http.get(`${CIBLE}/creneaux?zone=${zone}&date=${dateDans(entier(0, 13))}`,
      { tags: { nom: 'creneaux' } });
  } else if (tirage < 0.75) {
    // Les clients de la zone z ont les numéros z, z + 24, z + 48...
    const corps = JSON.stringify({
      client_id: zone + 24 * entier(0, 2082),
      zone_id: zone,
      date_livraison: dateDans(entier(0, 13)),
      creneau: entier(1, 8),
    });
    reponse = http.post(`${CIBLE}/rendez-vous`, corps, {
      headers: { 'Content-Type': 'application/json' },
      tags: { nom: 'rendez-vous' },
      // Un créneau complet (409) est une réponse normale, pas une erreur.
      responseCallback: http.expectedStatuses({ min: 200, max: 299 }, 409),
    });
  } else if (tirage < 0.90) {
    reponse = http.get(`${CIBLE}/livraisons?zone=${zone}&date=${dateDans(entier(0, 1))}`,
      { tags: { nom: 'livraisons' } });
  } else {
    reponse = http.get(`${CIBLE}/tournees?zone=${zone}&date=${dateDans(entier(0, 1))}`,
      { tags: { nom: 'tournees' } });
  }

  check(reponse, {
    'réponse attendue': (r) => r.status === 200 || r.status === 201 || r.status === 409,
  });
}
