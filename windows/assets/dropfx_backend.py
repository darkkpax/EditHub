#!/usr/bin/env python3
"""
DropFX Backend — HTTP server for sound library browsing.
Serves assets, waveforms, folder tree, and file copy operations.
Port: 8765 (configurable via DROPFX_PORT env var)
"""

import os
import sys
import json
import uuid
import shutil
import struct
import wave
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs, unquote
from pathlib import Path

PORT = int(os.environ.get("DROPFX_PORT", "8765"))
LIBRARY_ROOT = os.environ.get("DROPFX_LIBRARY", os.path.expanduser("~/EditHub/SFX"))

AUDIO_EXTENSIONS = {".wav", ".mp3", ".aiff", ".flac", ".ogg", ".aac", ".m4a"}

# ── Asset scanning ───────────────────────────────────────────────────────────

_asset_cache: dict = {}
_asset_id_map: dict = {}  # id -> path


def get_duration(path: str) -> float:
    """Get duration in seconds. Returns 0 on failure."""
    ext = os.path.splitext(path)[1].lower()
    try:
        if ext == ".wav":
            with wave.open(path, "r") as f:
                frames = f.getnframes()
                rate = f.getframerate()
                return frames / float(rate) if rate > 0 else 0
    except Exception:
        pass
    # Fallback: estimate from file size (rough for MP3)
    try:
        size = os.path.getsize(path)
        return size / (128 * 1024 / 8)  # assume 128kbps
    except Exception:
        return 0


def get_tags_from_name(name: str) -> list:
    """Derive simple tags from filename."""
    name_lower = name.lower()
    tags = []
    tag_keywords = {
        "kick": "kick",
        "snare": "snare",
        "hihat": "hihat",
        "hi-hat": "hihat",
        "bass": "bass",
        "pad": "pad",
        "synth": "synth",
        "vocal": "vocal",
        "vox": "vocal",
        "ambient": "ambient",
        "sfx": "sfx",
        "impact": "impact",
        "rise": "riser",
        "riser": "riser",
        "sweep": "sweep",
        "fx": "sfx",
        "loop": "loop",
        "one-shot": "oneshot",
        "oneshot": "oneshot",
        "beat": "beat",
        "music": "music",
    }
    for keyword, tag in tag_keywords.items():
        if keyword in name_lower and tag not in tags:
            tags.append(tag)
    return tags


def scan_library(root: str) -> list:
    """Scan the library root and return list of asset dicts."""
    assets = []
    if not os.path.exists(root):
        return assets

    for dirpath, dirnames, filenames in os.walk(root):
        # Skip hidden directories
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]

        for fname in filenames:
            ext = os.path.splitext(fname)[1].lower()
            if ext not in AUDIO_EXTENSIONS:
                continue
            full_path = os.path.join(dirpath, fname)
            asset_id = str(uuid.uuid5(uuid.NAMESPACE_URL, full_path))
            asset = {
                "id": asset_id,
                "name": fname,
                "path": full_path,
                "duration": get_duration(full_path),
                "tags": get_tags_from_name(os.path.splitext(fname)[0]),
                "folder": dirpath,
            }
            assets.append(asset)
            _asset_id_map[asset_id] = asset

    return assets


def get_folder_tree(root: str) -> list:
    """Return hierarchical folder tree."""
    if not os.path.exists(root):
        return []

    def build_tree(path: str) -> dict:
        name = os.path.basename(path) or path
        children = []
        try:
            for entry in sorted(os.scandir(path), key=lambda e: e.name):
                if entry.is_dir() and not entry.name.startswith("."):
                    children.append(build_tree(entry.path))
        except PermissionError:
            pass
        return {"name": name, "path": path, "children": children}

    try:
        entries = sorted(
            [e for e in os.scandir(root) if e.is_dir() and not e.name.startswith(".")],
            key=lambda e: e.name,
        )
        return [build_tree(e.path) for e in entries]
    except Exception:
        return []


def compute_waveform(path: str, buckets: int = 60) -> list:
    """Compute a simplified waveform array (0..1 per bucket)."""
    try:
        with wave.open(path, "r") as wf:
            n_channels = wf.getnchannels()
            sampwidth = wf.getsampwidth()
            n_frames = wf.getnframes()
            raw = wf.readframes(n_frames)

        if sampwidth == 2:
            fmt = f"<{len(raw) // 2}h"
            samples = struct.unpack(fmt, raw)
            max_val = 32768
        elif sampwidth == 1:
            samples = [b - 128 for b in raw]
            max_val = 128
        else:
            return [0.5] * buckets

        # Take every n_channels sample (mono mix)
        mono = [abs(samples[i]) for i in range(0, len(samples), n_channels)]
        if not mono:
            return [0.5] * buckets

        bucket_size = max(1, len(mono) // buckets)
        waveform = []
        for i in range(buckets):
            start = i * bucket_size
            end = start + bucket_size
            chunk = mono[start:end]
            if chunk:
                peak = max(chunk) / max_val
            else:
                peak = 0
            waveform.append(round(peak, 3))

        return waveform
    except Exception:
        # Return a fake waveform for non-WAV files
        import math
        return [round(0.3 + 0.5 * abs(math.sin(i * 0.4 + 0.5)), 3) for i in range(buckets)]


# ── HTTP handler ─────────────────────────────────────────────────────────────

class DropFXHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass  # Suppress default logging

    def send_json(self, data, status=200):
        body = json.dumps(data).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)

    def send_error_json(self, status, message):
        self.send_json({"error": message}, status)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/")
        qs = parse_qs(parsed.query)

        # Health check
        if path == "/health":
            self.send_json({"status": "ok", "library": LIBRARY_ROOT})
            return

        # Assets list
        if path == "/assets":
            assets = scan_library(LIBRARY_ROOT)
            q = qs.get("q", [""])[0].lower()
            folder = qs.get("folder", [""])[0]
            tags_filter = qs.get("tags", [""])[0].split(",") if qs.get("tags") else []

            filtered = []
            for a in assets:
                if q and q not in a["name"].lower():
                    continue
                if folder and not a["folder"].startswith(folder):
                    continue
                if tags_filter and tags_filter != [""]:
                    if not any(t in a["tags"] for t in tags_filter):
                        continue
                filtered.append(a)

            self.send_json(filtered)
            return

        # Waveform
        if path.startswith("/assets/") and path.endswith("/waveform"):
            asset_id = path[len("/assets/"):-len("/waveform")]
            asset = _asset_id_map.get(asset_id)
            if not asset:
                # Try to find by rescanning
                scan_library(LIBRARY_ROOT)
                asset = _asset_id_map.get(asset_id)
            if not asset:
                self.send_error_json(404, "Asset not found")
                return
            waveform = compute_waveform(asset["path"])
            self.send_json({"waveform": waveform})
            return

        # Audio stream
        if path.startswith("/assets/") and path.endswith("/audio"):
            asset_id = path[len("/assets/"):-len("/audio")]
            asset = _asset_id_map.get(asset_id)
            if not asset:
                scan_library(LIBRARY_ROOT)
                asset = _asset_id_map.get(asset_id)
            if not asset:
                self.send_error_json(404, "Asset not found")
                return
            try:
                file_path = asset["path"]
                file_size = os.path.getsize(file_path)
                ext = os.path.splitext(file_path)[1].lower()
                content_type_map = {
                    ".wav": "audio/wav",
                    ".mp3": "audio/mpeg",
                    ".aiff": "audio/aiff",
                    ".flac": "audio/flac",
                    ".ogg": "audio/ogg",
                    ".aac": "audio/aac",
                    ".m4a": "audio/mp4",
                }
                ct = content_type_map.get(ext, "audio/octet-stream")
                self.send_response(200)
                self.send_header("Content-Type", ct)
                self.send_header("Content-Length", str(file_size))
                self.send_header("Accept-Ranges", "bytes")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()
                with open(file_path, "rb") as f:
                    shutil.copyfileobj(f, self.wfile)
            except Exception as e:
                self.send_error_json(500, str(e))
            return

        # Folder tree
        if path == "/folders":
            tree = get_folder_tree(LIBRARY_ROOT)
            self.send_json(tree)
            return

        self.send_error_json(404, "Not found")

    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/")

        # Copy asset to destination
        if path.startswith("/assets/") and path.endswith("/copy"):
            asset_id = path[len("/assets/"):-len("/copy")]
            asset = _asset_id_map.get(asset_id)
            if not asset:
                scan_library(LIBRARY_ROOT)
                asset = _asset_id_map.get(asset_id)
            if not asset:
                self.send_error_json(404, "Asset not found")
                return

            content_len = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(content_len)
            try:
                data = json.loads(body)
                dest = data.get("dest", "")
                if not dest:
                    self.send_error_json(400, "Missing dest")
                    return
                os.makedirs(os.path.dirname(dest), exist_ok=True)
                shutil.copy2(asset["path"], dest)
                self.send_json({"success": True, "dest": dest})
            except Exception as e:
                self.send_error_json(500, str(e))
            return

        self.send_error_json(404, "Not found")


# ── Entry point ──────────────────────────────────────────────────────────────

def main():
    # Pre-scan library on startup
    print(f"DropFX backend starting on port {PORT}")
    print(f"Library root: {LIBRARY_ROOT}")
    threading.Thread(target=lambda: scan_library(LIBRARY_ROOT), daemon=True).start()

    server = ThreadingHTTPServer(("localhost", PORT), DropFXHandler)
    print(f"Listening on http://localhost:{PORT}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("DropFX backend shutting down")
        server.server_close()


if __name__ == "__main__":
    main()
