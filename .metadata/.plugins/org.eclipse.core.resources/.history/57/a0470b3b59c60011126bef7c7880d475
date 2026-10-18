import http from 'k6/http';
import { check } from 'k6';

const baseUrl = __ENV.BASE_URL || 'http://localhost:9092';
const vus = Number(__ENV.VUS || 50);
const duration = __ENV.DURATION || '1m';

export const options = {
  scenarios: {
    productsRead: {
      executor: 'constant-vus',
      vus,
      duration,
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'],
    checks: ['rate>0.99'],
  },
};

export default function () {
  const response = http.get(`${baseUrl}/api/products`, {
    tags: { workload: 'aws-products-read' },
  });

  check(response, {
    'products list returned': (res) => res.status === 200,
    'products response is JSON': (res) =>
      String(res.headers['Content-Type'] || '').includes('application/json'),
  });
}
