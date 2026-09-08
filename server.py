#!/usr/bin/env python3
"""
VTEC AI server — serves the app and stores users + chats in a local SQLite DB.

No dependencies (Python standard library only).
Run:      python server.py
Then open http://<this-machine-ip>:8080 in any office browser.

Data lives in vtec.db next to this file. Back that file up to back up everything.
"""
import hashlib
import json
import os
import secrets
import sqlite3
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, unquote

BASE = os.path.dirname(os.path.abspath(__file__))
DB = os.path.join(BASE, 'vtec.db')
PORT = 8080
DEFAULT_ADMIN = ('admin', 'admin123')
SALT = 'vtec-ai-lan-salt-v1'

db_lock = threading.Lock()
sessions = {}  # token -> username (in memory; restart = everyone signs in again)


def sha256(s):
    return hashlib.sha256((SALT + s).encode('utf-8')).hexdigest()


def query(fn):
    """Run fn(conn) with the global lock held; commit and close."""
    with db_lock:
        conn = sqlite3.connect(DB)
        conn.row_factory = sqlite3.Row
        try:
            r = fn(conn)
            conn.commit()
            return r
        finally:
            conn.close()


def init_db():
    def setup(conn):
        conn.execute('CREATE TABLE IF NOT EXISTS users ('
                     'username TEXT PRIMARY KEY, hash TEXT NOT NULL, '
                     'is_admin INTEGER NOT NULL DEFAULT 0, created INTEGER NOT NULL)')
        conn.execute('CREATE TABLE IF NOT EXISTS chats ('
                     'username TEXT NOT NULL, id TEXT NOT NULL, '
                     'data TEXT NOT NULL, updated INTEGER NOT NULL, '
                     'PRIMARY KEY (username, id))')
        n = conn.execute('SELECT COUNT(*) c FROM users').fetchone()['c']
        if n == 0:
            conn.execute('INSERT INTO users VALUES (?,?,?,?)',
                         (DEFAULT_ADMIN[0], sha256(DEFAULT_ADMIN[1]), 1, int(time.time() * 1000)))
            print('Created default admin account: admin / admin123  (change this password!)')
    query(setup)


class Handler(BaseHTTPRequestHandler):
    server_version = 'VTECAI/1.0'

    # ---------- helpers ----------
    def _json(self, code, obj):
        body = json.dumps(obj).encode('utf-8')
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(body)

    def _read_body(self):
        n = int(self.headers.get('Content-Length') or 0)
        raw = self.rfile.read(n) if n else b'{}'
        try:
            return json.loads(raw.decode('utf-8'))
        except Exception:
            return {}

    def _token(self):
        auth = self.headers.get('Authorization') or ''
        return auth[7:].strip() if auth.startswith('Bearer ') else ''

    def _user(self):
        return sessions.get(self._token())

    def _admin(self):
        u = self._user()
        if not u:
            return None
        row = query(lambda c: c.execute(
            'SELECT is_admin FROM users WHERE username=?', (u,)).fetchone())
        return u if row and row['is_admin'] else None

    # ---------- CORS ----------
    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, Authorization')
        self.end_headers()

    # ---------- GET ----------
    def do_GET(self):
        p = urlparse(self.path).path
        if p in ('/', '/index.html'):
            return self._serve_app()
        if p == '/api/me':
            u = self._user()
            if not u:
                return self._json(401, {'error': 'unauthorized'})
            row = query(lambda c: c.execute(
                'SELECT is_admin FROM users WHERE username=?', (u,)).fetchone())
            return self._json(200, {'username': u, 'isAdmin': bool(row['is_admin'])})
        if p == '/api/users':
            if not self._admin():
                return self._json(403, {'error': 'admin only'})
            rows = query(lambda c: c.execute(
                'SELECT username, is_admin FROM users').fetchall())
            return self._json(200, {r['username']: {'isAdmin': bool(r['is_admin'])} for r in rows})
        if p == '/api/chats':
            u = self._user()
            if not u:
                return self._json(401, {'error': 'unauthorized'})
            rows = query(lambda c: c.execute(
                'SELECT data FROM chats WHERE username=?', (u,)).fetchall())
            convs = {}
            for r in rows:
                try:
                    obj = json.loads(r['data'])
                    convs[obj.get('id') or 'c' + str(len(convs))] = obj
                except Exception:
                    pass
            return self._json(200, convs)
        return self._json(404, {'error': 'not found'})

    # ---------- POST ----------
    def do_POST(self):
        p = urlparse(self.path).path
        body = self._read_body()
        if p == '/api/login':
            u = str(body.get('username', '')).strip().lower()
            pw = str(body.get('password', ''))
            if not u or not pw:
                return self._json(400, {'error': 'Enter username and password'})
            row = query(lambda c: c.execute(
                'SELECT hash, is_admin FROM users WHERE username=?', (u,)).fetchone())
            if not row or row['hash'] != sha256(pw):
                return self._json(401, {'error': 'Unknown user or incorrect password.'})
            tok = secrets.token_hex(32)
            sessions[tok] = u
            return self._json(200, {'token': tok, 'username': u, 'isAdmin': bool(row['is_admin'])})
        if p == '/api/logout':
            sessions.pop(self._token(), None)
            return self._json(200, {'ok': True})
        if p == '/api/users':
            if not self._admin():
                return self._json(403, {'error': 'admin only'})
            u = str(body.get('username', '')).strip().lower()
            pw = str(body.get('password', ''))
            is_admin = 1 if body.get('isAdmin') else 0
            if not u or not pw:
                return self._json(400, {'error': 'Enter username and password'})
            try:
                query(lambda c: c.execute(
                    'INSERT INTO users VALUES (?,?,?,?)',
                    (u, sha256(pw), is_admin, int(time.time() * 1000))))
            except sqlite3.IntegrityError:
                return self._json(409, {'error': 'User already exists'})
            return self._json(200, {'ok': True})
        if p == '/api/chats':
            u = self._user()
            if not u:
                return self._json(401, {'error': 'unauthorized'})
            convs = body.get('convs')
            if not isinstance(convs, dict):
                return self._json(400, {'error': 'bad payload'})
            now = int(time.time() * 1000)

            def save(c):
                c.execute('DELETE FROM chats WHERE username=?', (u,))
                for cid, obj in convs.items():
                    if isinstance(obj, dict):
                        c.execute('INSERT OR REPLACE INTO chats VALUES (?,?,?,?)',
                                  (u, str(cid), json.dumps(obj), now))
            query(save)
            return self._json(200, {'ok': True})
        return self._json(404, {'error': 'not found'})

    # ---------- DELETE ----------
    def do_DELETE(self):
        p = urlparse(self.path).path
        if p.startswith('/api/users/'):
            name = unquote(p[len('/api/users/'):]).strip().lower()
            if not self._admin():
                return self._json(403, {'error': 'admin only'})

            def delete(c):
                row = c.execute('SELECT is_admin FROM users WHERE username=?', (name,)).fetchone()
                if not row:
                    return 'missing'
                admins = c.execute('SELECT COUNT(*) a FROM users WHERE is_admin=1').fetchone()['a']
                if row['is_admin'] and admins <= 1:
                    return 'last-admin'
                c.execute('DELETE FROM users WHERE username=?', (name,))
                c.execute('DELETE FROM chats WHERE username=?', (name,))
                return 'ok'
            r = query(delete)
            if r == 'missing':
                return self._json(404, {'error': 'No such user'})
            if r == 'last-admin':
                return self._json(409, {'error': 'Cannot delete the last admin account.'})
            return self._json(200, {'ok': True})
        return self._json(404, {'error': 'not found'})

    # ---------- app ----------
    def _serve_app(self):
        path = os.path.join(BASE, 'index.html')
        try:
            with open(path, 'rb') as f:
                data = f.read()
        except OSError:
            return self._json(500, {'error': 'index.html not found next to server.py'})
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt, *args):
        print('[%s] %s' % (self.log_date_time_string(), fmt % args))


if __name__ == '__main__':
    init_db()
    srv = ThreadingHTTPServer(('0.0.0.0', PORT), Handler)
    print('VTEC AI server running on port %d' % PORT)
    print('Open http://<this-machine-ip>:%d in any office browser' % PORT)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
