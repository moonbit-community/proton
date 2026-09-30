#!/usr/bin/env python3
"""Check book consistency; optionally compile the published tutorial projects."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
from html.parser import HTMLParser
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parent.parent
BOOK = ROOT / 'website'
VERSION = re.search(r'title = "Proton ([^"]+)"', (BOOK / 'book.toml').read_text())[1]


def blocks(source, language):
    return re.findall(r'^```' + re.escape(language) + r'\n(.*?)^```', source, re.M | re.S)


def read(language, page):
    return (BOOK / 'content' / language / (page + '.md')).read_text()


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def check_static():
    en = {p.relative_to(BOOK / 'content/en') for p in (BOOK / 'content/en').rglob('*.md')}
    zh = {p.relative_to(BOOK / 'content/zh') for p in (BOOK / 'content/zh').rglob('*.md')}
    require(en == zh, 'English and Chinese page sets differ')
    require(f'title = "Proton {VERSION}"' in (BOOK / 'zh/book.toml').read_text(), 'Book titles disagree')
    commits = set()
    for language in ('en', 'zh'):
        summary = read(language, 'SUMMARY')
        require(len(re.findall(r'^- \[', summary, re.M)) == 6, 'Expected six top-level chapters')
        for relative in en:
            p = BOOK / 'content' / language / relative
            source = p.read_text()
            if relative.name != 'SUMMARY.md':
                require(str(relative) in summary, f'Page missing from navigation: {p}')
            prose = re.sub(r'```.*?```|`[^`]*`', '', source, flags=re.S)
            for target in re.findall(r'\]\(([^)]+)\)', prose):
                if re.match(r'^[a-z]+:|^#|^/', target):
                    continue
                target = target.split('#')[0]
                require((p.parent / target).exists(), f'Broken local link in {p}: {target}')
            if relative.parts[0] != 'release-notes':
                for version in re.findall(r'(?:Proton |proton(?:_[a-z_]+)?@)(\d+\.\d+\.\d+)', source):
                    require(version == VERSION, f'Stale version {version} in {p}')
                commits.update(re.findall(r'github.com/moonbit-community/proton/(?:tree|blob)/([0-9a-f]{40})', source))
            if relative.parts[0] in ('tutorial', 'examples', 'configuration'):
                other = (BOOK / 'content' / ('zh' if language == 'en' else 'en') / relative).read_text()
                for syntax in ('moonbit', 'javascript', 'json', 'sh', 'text'):
                    require(blocks(source, syntax) == blocks(other, syntax), f'{syntax} examples differ between translations: {relative}')
    require(len(commits) == 1, f'Expected one pinned release commit, got {commits}')
    commit = next(iter(commits))
    result = subprocess.run(['git', 'show', f'{commit}:proton/moon.mod'], cwd=ROOT, capture_output=True, text=True)
    require(result.returncode == 0 and f'version = "{VERSION}"' in result.stdout, 'Pinned source is not the documented release')
    for page in (BOOK / 'content/en/examples').glob('*.md'):
        if page.stem == 'index':
            continue
        result = subprocess.run(['git', 'show', f'{commit}:examples/{page.stem}/main.mbt'], cwd=ROOT, capture_output=True, text=True)
        require(result.returncode == 0, f'Missing pinned example: {page.stem}')
        source = re.sub(r'\s+', '', result.stdout)
        for code in blocks(page.read_text(), 'moonbit'):
            require(re.sub(r'\s+', '', code) in source, f'Example excerpt drifted: {page}')
    print(f'Book structure, links, translations and release {VERSION} passed', flush=True)


def check_html():
    class Links(HTMLParser):
        def __init__(self):
            super().__init__()
            self.links, self.ids = [], set()

        def handle_starttag(self, tag, attrs):
            attrs = dict(attrs)
            if 'id' in attrs:
                self.ids.add(attrs['id'])
            if tag == 'a' and 'href' in attrs:
                self.links.append(attrs['href'])

    root = (BOOK / 'dist').resolve()
    pages = {}
    for page in root.rglob('*.html'):
        parsed = Links()
        parsed.feed(page.read_text())
        pages[page] = parsed
    require(root / 'index.html' in pages and root / 'zh/index.html' in pages, 'Build both books before --html')
    for page, parsed in pages.items():
        if page.name in ('print.html', '404.html'):
            continue
        for link in parsed.links:
            url = urlsplit(link)
            if url.scheme or url.netloc:
                continue
            if url.path.startswith('/proton/'):
                destination = root / url.path[len('/proton/'):]
            else:
                require(not url.path.startswith('/'), f'Unexpected site root: {link}')
                destination = (page.parent / url.path).resolve() if url.path else page
            if destination.is_dir():
                destination /= 'index.html'
            require(destination.exists(), f'Broken generated link in {page}: {link}')
            if url.fragment and destination in pages:
                require(unquote(url.fragment) in pages[destination].ids, f'Broken anchor in {page}: {link}')
    print('Generated HTML page links and anchors passed', flush=True)


def run(command, cwd, capture=False):
    print('+ ' + ' '.join(map(str, command)), flush=True)
    result = subprocess.run(command, cwd=cwd, env={**os.environ, 'PROTON_NO_UPDATE_CHECK': '1'},
                            text=True, stdout=subprocess.PIPE if capture else None)
    require(result.returncode == 0, f'Failed ({result.returncode}): {command}')
    return result.stdout or ''


def check_cli(cli):
    require(run([cli, '--version'], ROOT, True).strip() == f'proton_cli {VERSION}', 'Install the documented registry CLI version')
    for command in ([], ['new'], ['dev'], ['build'], ['package'], ['doctor'], ['cef', 'setup'], ['cef', 'requirements'], ['updater', 'public-key']):
        help_text = run([cli, *command, '--help'], ROOT, True)
        help_text = re.sub(r'--\[no-\]([a-z-]+)', r'--\1 --no-\1', help_text)
        for option in set(re.findall(r'--[a-z][a-z-]*', help_text)):
            for lang in ('en', 'zh'):
                reference = read(lang, 'command-line-interface/commands')
                if command:
                    reference = reference.split('## `' + ' '.join(command) + '`', 1)[1].split('\n## ', 1)[0]
                require(option in reference or option in ('--help', '--cwd'), f'Undocumented {command} option: {option}')


def check_tutorials(cli):
    temp = Path(tempfile.mkdtemp(prefix='proton-book-'))
    print(f'Tutorial artifacts: {temp}', flush=True)
    success = False
    try:
        run([cli, 'new', 'minimal', '--template', 'minimal', '--yes', '--no-git', '--no-check'], temp)
        app = temp / 'minimal'
        module = app / 'moon.mod'
        module.write_text(module.read_text().replace('import {', f'import {{\n  "moonbit-community/proton_contract@{VERSION}",\n  "moonbit-community/proton_ext@{VERSION}",'))
        original_pkg = (app / 'app/moon.pkg').read_text()
        run(['moon', 'update'], app)
        for page in ('first-app', 'commands-events', 'windows', 'capabilities'):
            text = read('en', 'tutorial/' + page)
            packages = [b for b in blocks(text, 'text') if b.startswith('import {')]
            (app / 'app/moon.pkg').write_text(packages[0] if packages else original_pkg)
            code = blocks(text, 'moonbit')[0]
            (app / 'app/main.mbt').write_text(code)
            run(['moon', 'check', '--target', 'native'], app)
            if page == 'commands-events':
                event = read('en', 'tutorial/events')
                parts = blocks(event, 'moonbit')
                code = code.replace('///|\nasync fn main', parts[0] + '\n///|\nasync fn main')
                code = re.sub(r'registrar.bind\(greet,.*?\n    \}\)', parts[1].strip(), code, flags=re.S)
                js = '\n'.join('    #|  ' + line for line in blocks(event, 'javascript')[0].splitlines())
                code = re.sub(r'(    #\|<script>\n).*?(    #\|</script>)', lambda m: m[1] + js + '\n' + m[2], code, flags=re.S)
                (app / 'app/main.mbt').write_text(code)
                run(['moon', 'check', '--target', 'native'], app)
            if page == 'windows':
                variants = blocks(text, 'moonbit')
                code = code.replace('width=480,', 'open_on_start=false,\n    width=480,').replace('.run_or_abort()', variants[1].strip() + '\n' + variants[2].strip() + '\n.run_or_abort()')
                (app / 'app/main.mbt').write_text(code)
                run(['moon', 'check', '--target', 'native'], app)
        run([cli, 'new', 'todo', '--template', 'isomorphic', '--yes', '--no-git', '--no-check'], temp)
        todo = temp / 'todo'
        parts = blocks(read('en', 'tutorial/isomorphic'), 'moonbit')
        for file, code in [('shared/todo_contract.mbt', parts[0]), ('backend/todo/backend.mbt', parts[1]), ('backend/todo/backend_wbtest.mbt', parts[6])]:
            with (todo / file).open('a') as out:
                out.write('\n' + code)
        file = todo / 'backend/todo/commands.mbt'
        code = file.read_text(); pos = code.rfind('}')
        file.write_text(code[:pos] + parts[2] + '\n' + code[pos:])
        file = todo / 'frontend/main/main.mbt'; code = file.read_text()
        require('enum Msg {' in code and 'match msg {' in code, 'Template message structure changed')
        code = code.replace('enum Msg {', 'enum Msg {\n' + parts[3], 1).replace('match msg {', 'match msg {\n' + parts[4], 1)
        marker = 'div(class="todo-toolbar", ['
        require(marker in code, 'Template toolbar changed')
        code = code.replace(marker, marker + '\n' + parts[5], 1)
        file.write_text(code)
        run(['moon', 'update'], todo)
        run(['moon', 'check', '--target', 'js,native'], todo)
        run(['moon', '-C', 'backend', 'test', 'todo', '--target', 'native'], todo)
        run(['moon', '-C', 'frontend', 'test', '--target', 'js'], todo)
        # Decode the actual complete configuration examples using the published parser.
        config = temp / 'config'; config.mkdir()
        (config / 'moon.mod').write_text(f'name = "book/config_check"\nversion = "0.0.0"\nimport {{ "moonbit-community/proton_config@{VERSION}", }}\n')
        (config / 'moon.pkg').write_text('import { "moonbit-community/proton_config" @config, } for "test"\nsupported_targets = "native"\n')
        tests = []
        for index, code in enumerate(blocks(read('en', 'configuration/project'), 'json')):
            json.loads(code)
            tests.append('test "configuration ' + str(index) + '" {\n ignore(@config.load_project_config_from_text(' + json.dumps(code) + ', "."))\n}\n')
        (config / 'config_test.mbt').write_text('\n///|\n'.join(tests))
        run(['moon', 'update'], config)
        run(['moon', 'test', '--target', 'native'], config)
        success = True
    finally:
        if success:
            shutil.rmtree(temp)
        else:
            print(f'Failed tutorial project retained at {temp}', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--html', action='store_true', help='Validate built page links and anchors')
    parser.add_argument('--cli', help='Published CLI executable for help and version checks')
    parser.add_argument('--tutorials', action='store_true', help='Compile both templates and tutorial changes against the registry')
    args = parser.parse_args()
    check_static()
    if args.html:
        check_html()
    if args.cli:
        check_cli(str(Path(args.cli).resolve()))
    if args.tutorials:
        require(args.cli is not None, '--tutorials requires --cli')
        check_tutorials(str(Path(args.cli).resolve()))
