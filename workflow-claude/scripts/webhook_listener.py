#!/usr/bin/env python3
import hashlib
import hmac
import json
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

# Format : "nom_repo_github": ("chemin_local", "branche_a_surveiller")
REPO_MAP = {
    # "ton-compte/nom-du-repo": ("/chemin/vers/le/clone/local", "dev"),
    # "ton-compte/autre-repo": ("/chemin/vers/autre-clone", "dev"),
}

WEBHOOK_SECRET = b"CHANGE_MOI_EN_UN_SECRET_ALEATOIRE"

PORT = 4949


def verify_signature(payload_body, signature_header):
    if not signature_header:
        return False
    hash_object = hmac.new(WEBHOOK_SECRET, msg=payload_body, digestmod=hashlib.sha256)
    expected_signature = "sha256=" + hash_object.hexdigest()
    return hmac.compare_digest(expected_signature, signature_header)


def do_pull(repo_path, branch):
    print(f"[pull] {repo_path} ({branch})")
    result = subprocess.run(
        ["git", "-C", repo_path, "fetch", "origin", branch],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        print(f"[erreur fetch] {result.stderr}")
        return

    current_branch = subprocess.run(
        ["git", "-C", repo_path, "rev-parse", "--abbrev-ref", "HEAD"],
        capture_output=True, text=True
    ).stdout.strip()

    if current_branch == branch:
        result = subprocess.run(
            ["git", "-C", repo_path, "pull", "origin", branch],
            capture_output=True, text=True
        )
        if result.returncode == 0:
            print(f"[ok] {repo_path} mis à jour (branche active).")
        else:
            print(f"[conflit/erreur] {repo_path} : {result.stderr}")
    else:
        result = subprocess.run(
            ["git", "-C", repo_path, "fetch", "origin", f"{branch}:{branch}"],
            capture_output=True, text=True
        )
        if result.returncode == 0:
            print(f"[ok] {repo_path} : réf locale de '{branch}' mise à jour (branche non active).")
        else:
            print(f"[erreur] {repo_path} : {result.stderr}")


class WebhookHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers.get("Content-Length", 0))
        payload_body = self.rfile.read(content_length)
        signature = self.headers.get("X-Hub-Signature-256")

        if not verify_signature(payload_body, signature):
            self.send_response(401)
            self.end_headers()
            self.wfile.write(b"Signature invalide")
            return

        event = self.headers.get("X-GitHub-Event")
        if event != "push":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"Event ignore")
            return

        try:
            data = json.loads(payload_body)
        except json.JSONDecodeError:
            self.send_response(400)
            self.end_headers()
            return

        repo_full_name = data.get("repository", {}).get("full_name", "")
        ref = data.get("ref", "")
        pushed_branch = ref.replace("refs/heads/", "")

        if repo_full_name in REPO_MAP:
            local_path, watched_branch = REPO_MAP[repo_full_name]
            if pushed_branch == watched_branch:
                do_pull(local_path, watched_branch)
            else:
                print(f"[ignore] Push sur {repo_full_name}:{pushed_branch}, on surveille {watched_branch}")
        else:
            print(f"[ignore] Repo inconnu : {repo_full_name}")

        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"OK")

    def log_message(self, format, *args):
        pass


if __name__ == "__main__":
    server = HTTPServer(("localhost", PORT), WebhookHandler)
    print(f"Ecoute des webhooks sur http://localhost:{PORT} ...")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nArret.")
        sys.exit(0)
