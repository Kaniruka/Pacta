#!/usr/bin/env python3
"""Check the public App/MCP deployment contract without creating a grant."""

import argparse
import json
import os
from pathlib import Path
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import Request, urlopen


def read_public_config(path):
    text = path.read_text(encoding="utf-8-sig")
    if path.suffix == ".json":
        source = json.loads(text)
    else:
        source = {}
        for line in text.splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                name, value = line.split("=", 1)
                source[name.strip()] = value.strip().strip("\"'")
    if not isinstance(source, dict):
        raise ValueError("Configuration must be an object")
    url = str(source.get("SUPABASE_URL", "")).strip().rstrip("/")
    key = str(source.get("SUPABASE_PUBLISHABLE_KEY", "")).strip()
    parsed = urlsplit(url)
    if (parsed.scheme != "https" or not parsed.hostname or parsed.username
            or parsed.password or parsed.path or parsed.query or parsed.fragment):
        raise ValueError("SUPABASE_URL must be an HTTPS origin without credentials or path")
    if key.startswith("sb_publishable_"):
        if len(key) <= len("sb_publishable_"):
            raise ValueError("Publishable key is empty")
    else:
        # Legacy anon JWTs are public; never export a service-role JWT.
        import base64
        try:
            payload = key.split(".")[1]
            claims = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
        except (IndexError, ValueError, UnicodeError):
            raise ValueError("Expected a publishable key or legacy anon key") from None
        if not isinstance(claims, dict) or claims.get("role") != "anon":
            raise ValueError("Only the public anon role may be used in a client build")
    return {"SUPABASE_URL": url, "SUPABASE_PUBLISHABLE_KEY": key}


def fetch(url, data=None, headers=None):
    request = Request(url, data=data, headers={"Content-Type": "application/json", **(headers or {})})
    try:
        response = urlopen(request, timeout=20)
    except HTTPError as error:
        response = error
    with response:
        # Do not follow a proxy/issuer redirect silently.
        if response.geturl() != url:
            raise ValueError("Endpoint redirected; check the canonical deployment URL")
        return response.status, response.headers, json.load(response)


def verify(config):
    status, _, settings = fetch(config["SUPABASE_URL"] + "/auth/v1/settings",
                              headers={"apikey": config["SUPABASE_PUBLISHABLE_KEY"]})
    if status != 200 or not isinstance(settings, dict):
        raise ValueError("Public key is not accepted by the selected App Auth deployment")
    issuer = config["SUPABASE_URL"] + "/functions/v1/national-focus-mcp"
    resource = issuer + "/mcp"
    status, _, metadata = fetch(issuer + "/resource-metadata")
    if (status != 200 or not isinstance(metadata, dict) or metadata.get("resource") != resource
            or metadata.get("authorization_servers") != [issuer]
            or metadata.get("scopes_supported") != ["national_focus:read"]):
        raise ValueError("Resource discovery does not match the App deployment")
    status, _, oauth = fetch(issuer + "/.well-known/openid-configuration")
    expected = {"issuer": issuer, "authorization_endpoint": issuer + "/authorize",
                "token_endpoint": issuer + "/token", "registration_endpoint": issuer + "/register"}
    if (status != 200 or not isinstance(oauth, dict) or any(oauth.get(k) != v for k, v in expected.items())
            or "S256" not in oauth.get("code_challenge_methods_supported", [])
            or "none" not in oauth.get("token_endpoint_auth_methods_supported", [])
            or oauth.get("scopes_supported") != ["national_focus:read"]):
        raise ValueError("OAuth discovery does not match the public issuer/PKCE/scope contract")
    status, headers, result = fetch(resource, b'{}')
    if (status != 401 or not isinstance(result, dict) or result.get("error") != "invalid_token"
            or f'resource_metadata="{issuer}/resource-metadata"' not in headers.get("WWW-Authenticate", "")):
        raise ValueError("Unauthenticated MCP request was not rejected with matching discovery")
    print(f"PASS: App public key, URL, resource, OAuth discovery, PKCE, scope and unauthenticated rejection: {resource}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, required=True, help="Local JSON or .env; values are never printed")
    parser.add_argument("--public-output", type=Path, help="Create a new JSON with only the two public build fields")
    args = parser.parse_args()
    try:
        config = read_public_config(args.config)
        verify(config)
        if args.public_output:
            args.public_output.parent.mkdir(parents=True, exist_ok=True)
            descriptor = os.open(args.public_output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(descriptor, "w", encoding="utf-8") as output:
                json.dump(config, output, indent=2)
                output.write("\n")
            print("PASS: public build configuration created; no TEST_* or server credentials exported")
    except (ValueError, OSError, URLError) as error:
        # Network exception text can contain proxy details; only expose its type.
        message = str(error) if isinstance(error, ValueError) else type(error).__name__
        print(f"FAIL: {message}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
