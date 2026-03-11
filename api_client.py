#!/usr/bin/env python3
"""AF64 API Client — all DB access goes through dpn-api."""

import os
import requests

API_BASE = os.environ.get("DPN_API_URL", "http://localhost:8080")
API_KEY = os.environ.get("DPN_API_KEY", "dpn-nova-2026")

_headers = {"X-API-Key": API_KEY}


def api_get(path, params=None):
    r = requests.get(f"{API_BASE}{path}", headers=_headers, params=params, timeout=30)
    r.raise_for_status()
    return r.json()


def api_post(path, data):
    r = requests.post(f"{API_BASE}{path}", headers=_headers, json=data, timeout=30)
    r.raise_for_status()
    return r.json()


def api_patch(path, data):
    r = requests.patch(f"{API_BASE}{path}", headers=_headers, json=data, timeout=30)
    r.raise_for_status()
    return r.json()
