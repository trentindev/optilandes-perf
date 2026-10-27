// Charge nominale : débit constant.
// Paramètres : DEBIT (requêtes par seconde, 10 par défaut), DUREE (3m par défaut).
// Exemple : docker compose run --rm -e DEBIT=20 -e DUREE=1m k6 run /scripts/nominal.js
import { parcoursUtilisateur, SEUILS } from './commun.js';

export const options = {
  scenarios: {
    nominal: {
      executor: 'constant-arrival-rate',
      rate: parseInt(__ENV.DEBIT || '10', 10),
      timeUnit: '1s',
      duration: __ENV.DUREE || '3m',
      preAllocatedVUs: 20,
      maxVUs: 300,
    },
  },
  thresholds: SEUILS,
  summaryTrendStats: ['avg', 'med', 'p(90)', 'p(95)', 'max'],
};

export default function () {
  parcoursUtilisateur();
}
