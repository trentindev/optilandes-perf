// Montée en charge : le débit augmente par paliers d'une minute.
// À observer pendant le test : docker stats, dans un autre terminal.
import { parcoursUtilisateur, SEUILS } from './commun.js';

export const options = {
  scenarios: {
    montee: {
      executor: 'ramping-arrival-rate',
      startRate: 5,
      timeUnit: '1s',
      preAllocatedVUs: 50,
      maxVUs: 500,
      stages: [
        { target: 10, duration: '1m' },
        { target: 20, duration: '1m' },
        { target: 40, duration: '1m' },
        { target: 60, duration: '1m' },
        { target: 80, duration: '1m' },
      ],
    },
  },
  thresholds: SEUILS,
  summaryTrendStats: ['avg', 'med', 'p(90)', 'p(95)', 'max'],
};

export default function () {
  parcoursUtilisateur();
}
