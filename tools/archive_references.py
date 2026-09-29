#!/usr/bin/env python3
"""Archive the explicitly selected public research URLs, never crawl recursively.
Research tooling only; not Meow-Chess application code. Requires requests and bs4.
Raw third-party material stays in ignored research/local; publish only our notes.
"""
import argparse
import hashlib
import json
import time
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse
import requests
from bs4 import BeautifulSoup

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--refresh', action='store_true')
    args = parser.parse_args()
    sources = json.loads((ROOT / 'research/sources.json').read_text())
    cache = ROOT / 'research/local'
    cache.mkdir(parents=True, exist_ok=True)
    manifest_path = cache / 'manifest.json'
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
    session = requests.Session()
    session.headers['User-Agent'] = 'Meow-Chess-research/0.1 (single-user reference archive)'
    for source in sources:
        key, url = source['id'], source['url']
        if key in manifest and not args.refresh:
            continue
        # Deliberately no credentials, member-data endpoints, recursive crawling or retries.
        if urlparse(url).scheme != 'https':
            raise ValueError('Only explicitly listed HTTPS references are supported')
        try:
            response = session.get(url, timeout=25)
            content_type = response.headers.get('content-type', '')
            extension = '.pdf' if 'pdf' in content_type else '.json' if 'json' in content_type else '.html'
            path = cache / (key + extension)
            path.write_bytes(response.content)
            text_path = None
            if 'html' in content_type and response.ok:
                soup = BeautifulSoup(response.content, 'html.parser')
                node = soup.select_one('article') or soup.select_one('main') or soup
                for tag in node.select('script,style,nav'):
                    tag.decompose()
                text_path = cache / (key + '.txt')
                text_path.write_text(node.get_text('\n', strip=True))
            manifest[key] = dict(url=url, final_url=response.url, status=response.status_code,
                retrieved_at=datetime.now(timezone.utc).isoformat(), content_type=content_type,
                bytes=len(response.content), sha256=hashlib.sha256(response.content).hexdigest(),
                raw_path=str(path.relative_to(ROOT)), text_path=str(text_path.relative_to(ROOT)) if text_path else None)
            print(key, response.status_code, len(response.content), flush=True)
        except requests.RequestException as error:
            manifest[key] = dict(url=url, error=str(error), retrieved_at=datetime.now(timezone.utc).isoformat())
            print(key, type(error).__name__, flush=True)
        manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
        time.sleep(0.6)

if __name__ == '__main__':
    main()
