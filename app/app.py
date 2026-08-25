"""node-monitor: a deliberately small workload for the delivery platform.

The application is not the point of this repository. It exists so the
pipeline has something real to build, sign, scan, promote and evidence.
"""
import os
import socket

import psutil
from flask import Flask, jsonify, Response
from prometheus_client import Gauge, Info, generate_latest, CONTENT_TYPE_LATEST

APP_VERSION = os.getenv("APP_VERSION", "0.0.0-dev")
ENVIRONMENT = os.getenv("ENVIRONMENT", "local")
CHANGE_REF = os.getenv("CHANGE_REF", "unset")

app = Flask(__name__)

cpu_percent = Gauge("node_monitor_cpu_percent", "CPU utilisation percent")
mem_percent = Gauge("node_monitor_memory_percent", "Memory utilisation percent")
disk_percent = Gauge("node_monitor_disk_percent", "Root filesystem utilisation percent")
build_info = Info("node_monitor_build", "Build and release provenance")
build_info.info({"version": APP_VERSION, "environment": ENVIRONMENT, "change_ref": CHANGE_REF})


def collect():
    return {
        "host": socket.gethostname(),
        "environment": ENVIRONMENT,
        "version": APP_VERSION,
        "change_ref": CHANGE_REF,
        "cpu_percent": psutil.cpu_percent(interval=0.1),
        "cpu_count": psutil.cpu_count(),
        "memory_percent": psutil.virtual_memory().percent,
        "memory_total_mb": round(psutil.virtual_memory().total / 1024 / 1024),
        "disk_percent": psutil.disk_usage("/").percent,
        "boot_time": psutil.boot_time(),
    }


@app.get("/")
def index():
    s = collect()
    return f"""<!doctype html>
<title>node-monitor</title>
<style>
 body{{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;background:#0e1116;color:#d7dde5;padding:2rem}}
 h1{{font-size:1.05rem;letter-spacing:.09em;text-transform:uppercase;color:#7aa2f7}}
 table{{border-collapse:collapse;margin-top:1rem}}
 td{{padding:.35rem 1.6rem .35rem 0;border-bottom:1px solid #1f2630}}
 .k{{color:#8b95a5}} .env{{color:#9ece6a}}
</style>
<h1>node-monitor</h1>
<table>
 <tr><td class="k">environment</td><td class="env">{s['environment']}</td></tr>
 <tr><td class="k">version</td><td>{s['version']}</td></tr>
 <tr><td class="k">change-ref</td><td>{s['change_ref']}</td></tr>
 <tr><td class="k">pod</td><td>{s['host']}</td></tr>
 <tr><td class="k">cpu</td><td>{s['cpu_percent']}% of {s['cpu_count']} cores</td></tr>
 <tr><td class="k">memory</td><td>{s['memory_percent']}% of {s['memory_total_mb']} MB</td></tr>
 <tr><td class="k">disk</td><td>{s['disk_percent']}%</td></tr>
</table>"""


@app.get("/api/stats")
def stats():
    return jsonify(collect())


@app.get("/healthz")
def healthz():
    return jsonify(status="ok"), 200


@app.get("/readyz")
def readyz():
    return jsonify(status="ready"), 200


@app.get("/metrics")
def metrics():
    cpu_percent.set(psutil.cpu_percent(interval=None))
    mem_percent.set(psutil.virtual_memory().percent)
    disk_percent.set(psutil.disk_usage("/").percent)
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
