#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Zenoo Sample Page & Index Generator
1. docs/samples/index.html (サンプル一覧目次) の生成
2. ビルドされた各サンプルの index.html へのメタデータ・Rubyコード注入
"""

import os
import re
import html
import sys

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SAMPLES_DIR = os.path.join(BASE_DIR, 'samples')
ORDER_FILE = os.path.join(SAMPLES_DIR, 'order.txt')
INDEX_TEMPLATE = os.path.join(BASE_DIR, 'tools', 'templates', 'sample_index.html')
DOCS_SAMPLES_DIR = os.path.join(BASE_DIR, 'docs', 'samples')

def parse_sample_metadata(filepath):
    filename = os.path.basename(filepath)
    name = os.path.splitext(filename)[0]

    category = "General"
    title = name.replace('_', ' ').title()
    desc = ""

    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    lines = content.splitlines()
    for line in lines[:15]:
        line_clean = line.strip()
        m_cat = re.match(r'^#\s*category\s*:\s*(.+)$', line_clean, re.IGNORECASE)
        if m_cat:
            category = m_cat.group(1).strip()
        m_title = re.match(r'^#\s*title\s*:\s*(.+)$', line_clean, re.IGNORECASE)
        if m_title:
            title = m_title.group(1).strip()
        m_desc = re.match(r'^#\s*(?:desc|description)\s*:\s*(.+)$', line_clean, re.IGNORECASE)
        if m_desc:
            desc = m_desc.group(1).strip()

    return {
        "name": name,
        "filename": filename,
        "filepath": filepath,
        "category": category,
        "title": title,
        "desc": desc,
        "code": content
    }

def load_sample_order():
    if not os.path.isfile(ORDER_FILE):
        return {}
    order = {}
    idx = 0
    with open(ORDER_FILE, 'r', encoding='utf-8') as f:
        for line in f:
            entry = line.strip()
            if not entry or entry.startswith('#'):
                continue
            name = os.path.splitext(entry)[0]
            if name not in order:
                order[name] = idx
                idx += 1
    return order

def get_all_samples():
    if not os.path.isdir(SAMPLES_DIR):
        return []
    order = load_sample_order()
    fallback_idx = len(order)
    files = [f for f in sorted(os.listdir(SAMPLES_DIR)) if f.endswith('.rb')]
    files.sort(key=lambda f: (order.get(os.path.splitext(f)[0], fallback_idx), f))
    return [parse_sample_metadata(os.path.join(SAMPLES_DIR, f)) for f in files]

def generate_index(samples):
    os.makedirs(DOCS_SAMPLES_DIR, exist_ok=True)
    with open(INDEX_TEMPLATE, 'r', encoding='utf-8') as f:
        template = f.read()

    categories = {}
    for s in samples:
        cat = s['category']
        if cat not in categories:
            categories[cat] = []
        categories[cat].append(s)

    content_html = []
    if not samples:
        content_html.append('<p class="empty-note">まだサンプルがありません。</p>')
    else:
        for cat, items in categories.items():
            content_html.append('<section class="category-section">')
            content_html.append(f'  <h2>{html.escape(cat)}</h2>')
            content_html.append('  <ul class="sample-list">')
            for item in items:
                href = f"{item['name']}/index.html"
                content_html.append('    <li class="sample-item">')
                content_html.append(f'      <a class="sample-link" href="{href}">{html.escape(item["title"])}</a>')
                if item['desc']:
                    content_html.append(f'      <span class="sample-desc">{html.escape(item["desc"])}</span>')
                content_html.append('    </li>')
            content_html.append('  </ul>')
            content_html.append('</section>')

    index_html = template.replace('{{CONTENT}}', '\n'.join(content_html))
    out_path = os.path.join(DOCS_SAMPLES_DIR, 'index.html')
    with open(out_path, 'w', encoding='utf-8') as f:
        f.write(index_html)
    print(f"Generated {out_path} ({len(samples)} sample(s))")

def inject_metadata_to_html(target_html_path, rb_path):
    if not os.path.isfile(target_html_path):
        raise FileNotFoundError(f"HTML not found: {target_html_path}")
    if not os.path.isfile(rb_path):
        raise FileNotFoundError(f"Ruby script not found: {rb_path}")

    meta = parse_sample_metadata(rb_path)
    escaped_code = html.escape(meta['code'])

    with open(target_html_path, 'r', encoding='utf-8') as f:
        content = f.read()

    content = content.replace('<!--TITLE-->', html.escape(meta['title']))
    content = content.replace('<!--CATEGORY-->', html.escape(meta['category']))
    content = content.replace('<!--DESCRIPTION-->', html.escape(meta['desc']))
    content = content.replace('<!--FILENAME-->', html.escape(meta['filename']))
    content = content.replace('<!--CODE-->', escaped_code)

    with open(target_html_path, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"Injected metadata & code into {target_html_path}")

def main():
    if len(sys.argv) > 1 and sys.argv[1] == '--list':
        for s in get_all_samples():
            print(s['name'])
        return

    if len(sys.argv) > 3 and sys.argv[1] == '--inject':
        inject_metadata_to_html(sys.argv[2], sys.argv[3])
        return

    samples = get_all_samples()
    generate_index(samples)

if __name__ == '__main__':
    main()
