import sys
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))

import pytest
from app import app as flask_app


@pytest.fixture
def client():
    flask_app.config["TESTING"] = True
    with flask_app.test_client() as c:
        yield c


def test_healthz(client):
    assert client.get("/healthz").status_code == 200


def test_readyz(client):
    assert client.get("/readyz").status_code == 200


def test_stats_shape(client):
    body = client.get("/api/stats").get_json()
    for key in ("cpu_percent", "memory_percent", "disk_percent", "version", "environment"):
        assert key in body


def test_metrics_exposes_prometheus_format(client):
    r = client.get("/metrics")
    assert r.status_code == 200
    assert b"node_monitor_cpu_percent" in r.data
