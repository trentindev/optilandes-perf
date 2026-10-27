// Pic soudain : 10 requêtes par seconde, puis 60 en 10 secondes pendant 1 minute, puis retour à 10.
import { parcoursUtilisateur, SEUILS } from './commun.js';

export const options = {
  scenarios: {
    pic: {
      executor: 'ramping-arrival-rate',
      startRate: 10,
      timeUnit: '1s',
      preAllocatedVUs: 50,
      maxVUs: 500,
      stages: [
        { target: 10, duration: '1m' },
        { target: 60, duration: '10s' },
        { target: 60, duration: '1m' },
        { target: 10, duration: '10s' },
        { target: 10, duration: '1m' },
      ],
    },
  },
  thresholds: SEUILS,
  summaryTrendStats: ['avg', 'med', 'p(90)', 'p(95)', 'max'],
};

export default function () {
  parcoursUtilisateur();
}
