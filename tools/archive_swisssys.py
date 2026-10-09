#!/usr/bin/env python3
"""Archive public SwissSys documentation and product pages for local reference.

Bounded to docs.chessroster.com/swisssys/ and www.chessroster.com/swisssys.
Discover from sitemap, navigation and recursive links. No login, forms, installers,
API calls or external-site recursion. Preserve raw HTML + extracted article text;
this is a searchable reference archive, not an offline executable website.
"""
import argparse
from collections import deque
from datetime import datetime, timezone
import hashlib
import html
import json
from pathlib import Path
import time
from urllib.parse import urljoin, urlsplit, urlunsplit
from urllib.robotparser import RobotFileParser
import xml.etree.ElementTree as ET

import requests
from bs4 import BeautifulSoup

ROOT = Path(__file__).resolve().parents[1]
AGENT = 'Meow-Chess-Reference/1.0'


def canonical(url):
    p = urlsplit(url)
    path = p.path
    if p.netloc == 'docs.chessroster.com' and not Path(path).suffix:
        path = path.rstrip('/') + '/'
    query = '' if p.netloc in ['docs.chessroster.com', 'www.chessroster.com'] else p.query
    return urlunsplit((p.scheme, p.netloc.lower(), path, query, ''))


def in_scope(url):
    p = urlsplit(url)
    return p.scheme == 'https' and (
        p.netloc == 'docs.chessroster.com' and p.path.startswith('/swisssys/') or
        p.netloc == 'www.chessroster.com' and
        (p.path == '/swisssys' or p.path.startswith('/swisssys/')))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cache', type=Path, default=ROOT / 'research/local/swisssys-site')
    args = parser.parse_args()
    cache = args.cache.resolve()
    cache.mkdir(parents=True, exist_ok=True)
    session = requests.Session()
    session.headers['User-Agent'] = AGENT
    manifest_path = cache / 'manifest.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8')) if manifest_path.exists() else {}
    robots = {}
    for host in ['docs.chessroster.com', 'www.chessroster.com']:
        u = 'https://' + host + '/robots.txt'
        r = session.get(u, timeout=25)
        (cache / (host + '-robots.txt')).write_text(r.text, encoding='utf-8')
        rp = RobotFileParser(u)
        if r.ok:
            rp.parse(r.text.splitlines())
        elif r.status_code == 404:
            rp.parse([])
        else:
            raise RuntimeError(f'Cannot establish robots policy: {u} {r.status_code}')
        robots[host] = rp
    sitemap = session.get('https://docs.chessroster.com/sitemap.xml', timeout=25)
    sitemap.raise_for_status()
    (cache / 'sitemap.xml').write_bytes(sitemap.content)
    sitemap_urls = [canonical(e.text) for e in ET.fromstring(sitemap.content).iter()
                    if e.tag.endswith('}loc') and e.text and in_scope(e.text)]
    nav = json.loads((ROOT / 'research/swisssys-navigation.json').read_text(encoding='utf-8'))
    seeds = sorted(set(sitemap_urls + [canonical(n['url']) for n in nav] +
                       ['https://www.chessroster.com/swisssys',
                        'https://www.chessroster.com/swisssys/downloads']))
    queue, seen, scheduled, external, assets = deque(seeds), set(), set(seeds), set(), set()
    while queue:
        url = queue.popleft()
        if url in seen:
            continue
        seen.add(url)
        if len(seen) > 1000:
            raise RuntimeError('Discovery limit reached; investigate before extending scope')
        p = urlsplit(url)
        if not robots[p.netloc].can_fetch(AGENT, url):
            manifest[url] = {'status': 'robots-disallowed'}
            continue
        key = hashlib.sha256(url.encode()).hexdigest()[:16]
        raw = cache / (key + '.html')
        record = manifest.get(url, {})
        if not (record.get('status') == 200 and raw.exists()):
            try:
                r = session.get(url, timeout=25, allow_redirects=False)
                record = {'status': r.status_code, 'retrieved_at': datetime.now(timezone.utc).isoformat(),
                          'content_type': r.headers.get('content-type', ''), 'bytes': len(r.content)}
                raw.write_bytes(r.content)
                record.update(raw=raw.name, sha256=hashlib.sha256(r.content).hexdigest())
                if r.is_redirect:
                    target = canonical(urljoin(url, r.headers['location']))
                    record['redirect'] = target
                    if in_scope(target) and target not in scheduled:
                        queue.append(target)
                        scheduled.add(target)
                    else: external.add(target)
                manifest[url] = record
            except requests.RequestException as error:
                manifest[url] = {'status': 'error', 'error': str(error)}
                record = manifest[url]
            manifest_path.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
            time.sleep(.6)
        if record.get('status') == 200 and 'html' in record.get('content_type', ''):
            soup = BeautifulSoup(raw.read_bytes(), 'html.parser')
            article = soup.find('article') or soup.find('main') or soup
            title = soup.find('h1') or soup.find('title')
            record['title'] = title.get_text(' ', strip=True) if title else url
            record['headings'] = [h.get_text(' ', strip=True) for h in article.select('h2,h3,h4')]
            for a in soup.select('a[href]'):
                target = canonical(urljoin(url, a['href']))
                ext = Path(urlsplit(target).path).suffix.lower()
                if in_scope(target) and ext not in ['.exe','.msi','.zip','.pdf','.png','.jpg','.webp']:
                    if target not in scheduled:
                        queue.append(target)
                        scheduled.add(target)
                elif urlsplit(target).scheme in ['https', 'http']:
                    external.add(target)
            for el in article.select('img[src],a[href]'):
                src = el.get('src') or el.get('href')
                asset = canonical(urljoin(url, src))
                if Path(urlsplit(asset).path).suffix.lower() in ['.png','.jpg','.jpeg','.webp','.gif','.svg','.pdf']:
                    assets.add(asset)
            for el in article.select('script,style,nav'):
                el.decompose()
            txt = article.get_text('\n', strip=True)
            (cache / (key + '.txt')).write_text(txt, encoding='utf-8')
            record.update(text=key + '.txt', text_sha256=hashlib.sha256(txt.encode()).hexdigest(),
                          text_chars=len(txt), review='not yet exhaustively reviewed')
        if len(seen) % 25 == 0:
            print(f'{len(seen)} pages processed, {len(queue)} pages queued', flush=True)
        manifest_path.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    # Only same-host article images/PDFs; external assets are inventoried, not mirrored.
    asset_manifest = {}
    for url in sorted(assets):
        p = urlsplit(url)
        if p.netloc not in robots or not robots[p.netloc].can_fetch(AGENT, url):
            asset_manifest[url] = {'status': 'external-or-disallowed'}
            continue
        try:
            r = session.get(url, timeout=25, allow_redirects=False)
            key = hashlib.sha256(url.encode()).hexdigest()[:16] + Path(p.path).suffix
            (cache / key).write_bytes(r.content)
            asset_manifest[url] = dict(status=r.status_code, file=key,
                sha256=hashlib.sha256(r.content).hexdigest(), bytes=len(r.content))
        except requests.RequestException as error:
            asset_manifest[url] = dict(status='error', error=str(error))
        time.sleep(.6)
    (cache / 'assets.json').write_text(json.dumps(asset_manifest, indent=2) + '\n', encoding='utf-8')
    (cache / 'external-links.json').write_text(json.dumps(sorted(external), indent=2) + '\n', encoding='utf-8')
    coverage = dict(retrieved_at=datetime.now(timezone.utc).isoformat(),
        scope=['https://docs.chessroster.com/swisssys/', 'https://www.chessroster.com/swisssys'],
        navigation_count=len(nav), sitemap_count=len(set(sitemap_urls)),
        discovered_pages=len(manifest), successful_pages=sum(r.get('status') == 200 for r in manifest.values()),
        failures={u:r['status'] for u,r in manifest.items() if r.get('status') != 200},
        missing_sitemap_urls=sorted(set(sitemap_urls)-set(manifest)),
        missing_navigation_urls=sorted({canonical(n['url']) for n in nav}-set(manifest)),
        article_assets=len(assets), external_links=len(external), pages=manifest)
    (cache / 'coverage.json').write_text(json.dumps(coverage, indent=2) + '\n', encoding='utf-8')
    rows = ['<!doctype html><html lang="en"><meta charset="utf-8"><title>SwissSys local reference</title>',
            '<h1>SwissSys local reference</h1><p>Saved content is not reviewed/implemented feature coverage. Open text for offline reading; original HTML may reference network assets.</p><ul>']
    for u,r in sorted(manifest.items(), key=lambda item: item[1].get('title', item[0])):
        rows.append('<li>' + html.escape(r.get('title',u)) + ' — ' + str(r['status']) +
                    (f' <a href="{r["text"]}">Local text</a>' if r.get('text') else '') +
                    f' <a href="{html.escape(u)}">Source</a></li>')
    (cache / 'index.html').write_text('\n'.join(rows) + '</ul></html>\n', encoding='utf-8')
    print(json.dumps({k:v for k,v in coverage.items() if k != 'pages'}, indent=2), flush=True)


if __name__ == '__main__':
    main()
