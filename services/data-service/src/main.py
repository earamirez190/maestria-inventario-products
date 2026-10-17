from fastapi import FastAPI, Request
import time
import random
import os
import requests

from opentelemetry import trace
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.requests import RequestsInstrumentor
from opentelemetry.sdk.resources import SERVICE_NAME, Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter

# Setup OTel
service_name = os.getenv("OTEL_SERVICE_NAME", "data-service")
resource = Resource(attributes={SERVICE_NAME: service_name})
provider = TracerProvider(resource=resource)
trace.set_tracer_provider(provider)

otlp_endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4317")
span_exporter = OTLPSpanExporter(endpoint=notlp_endpoint := os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4317"))
processor = BatchSpanProcessor(span_exporter)
provider.add_span_processor(processor)

tracer = trace.get_tracer(__name__)

app = FastAPI()
FastAPIInstrumentor.instrument_app(app)
RequestsInstrumentor().instrument()

@app.get('/health')
def health():
    return {"status": "ok"}

@app.get('/items/{item_id}')
def get_item(item_id: int, request: Request):
    # Simulate DB access with a child span using OTel semantic attributes
    with tracer.start_as_current_span("db.query", attributes={
        "db.system": "postgresql",
        "db.name": os.getenv("DB_NAME", "example_db"),
        "db.operation": "SELECT",
        "db.statement": f"SELECT * FROM items WHERE id={item_id}",
    }):
        # simulate latency
        time.sleep(random.uniform(0.01, 0.1))

    # Simulated downstream call
    with tracer.start_as_current_span("external.call"):
        # add random error simulation
        if random.random() < 0.05:
            # simulate an error
            raise Exception("simulated error")

        return {"item_id": item_id, "value": f"Item {item_id}"}
