import http from 'k6/http';
import { check } from 'k6';

const baseUrl = __ENV.BASE_URL || 'http://localhost:9092';
const vus = Number(__ENV.VUS || 50);
const duration = __ENV.DURATION || '1m';

export const options = {
  scenarios: {
    products: {
      executor: 'constant-vus',
      vus,
      duration,
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'],
  },
};

export default function () {
  const sequence = `${__VU}-${__ITER}-${Date.now()}`;
  const payload = JSON.stringify({
    name: `benchmark-product-${sequence}`,
    quantity: 10,
    price: 25.5,
  });

  const response = http.post(`${baseUrl}/api/products`, payload, {
    headers: { 'Content-Type': 'application/json' },
    tags: { workload: 'benchmark-products' },
  });

  check(response, {
    'product created': (res) => res.status === 201,
  });
}
