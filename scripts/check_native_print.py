#!/usr/bin/env python3
"""Sends real jobs through the app's printing plugin to a stand-in printer.

Linux runs a private CUPS server on its own socket, so the computer's real
printers cannot be reached and nothing needs root. Windows (a print-to-PDF
queue on a file port) and macOS (a queue on the system CUPS) change the
computer, so they run only in CI.

  check_native_print.py             run the spool test, then read every job
  check_native_print.py --flatpak   run the installed Flatpak and require that
                                    it can see the stand-in printer
"""
import argparse
import contextlib
import getpass
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
from print_checks import job_issues  # noqa: E402

root = Path(__file__).resolve().parent.parent
QUEUE = 'meow-virtual'
FLATPAK_APP = 'org.meowchess.meow_chess'
SPEC = 'integration_test/native/print_spool_test.dart'


def run(*command, **options):
    print('+', ' '.join(str(c) for c in command), flush=True)
    return subprocess.run([str(c) for c in command], check=True, **options)


def wait_until(ready, what, seconds=30):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if ready():
            return
        time.sleep(0.25)
    raise SystemExit(f'Timed out waiting for {what}')


def collect_spool_jobs(spool, out):
    """CUPS keeps each job's document as d<job>-001 under PreserveJobFiles."""
    for index, document in enumerate(sorted(spool.glob('d*-001'))):
        shutil.copy(document, out / f'job-{index}.pdf')


@contextlib.contextmanager
def linux_queue(work):
    """A private cupsd. The socket path must fit a Unix socket's 107 bytes,
    so it cannot sit under an arbitrarily long temporary directory."""
    import grp  # Unix only; this file also runs on Windows.

    short = Path(os.environ.get('XDG_RUNTIME_DIR') or '/tmp')
    socket = short / f'meow-cups-{os.getpid()}.sock'
    for name in ['spool/tmp', 'cache', 'state', 'logs', 'conf/ppd', 'conf/ssl']:
        (work / name).mkdir(parents=True)
    user = getpass.getuser()
    group = grp.getgrgid(os.getgid()).gr_name
    (work / 'conf/cupsd.conf').write_text(f"""LogLevel warn
Listen {socket}
Browsing Off
WebInterface No
DefaultAuthType None
PreserveJobFiles Yes
PreserveJobHistory Yes
<Location />
  Order allow,deny
  Allow all
</Location>
<Policy default>
  <Limit All>
    AuthType None
    Order allow,deny
    Allow all
  </Limit>
</Policy>
""", encoding='utf-8')
    (work / 'conf/cups-files.conf').write_text(f"""FileDevice Yes
User {user}
Group {group}
SystemGroup {group}
ServerRoot {work}/conf
RequestRoot {work}/spool
TempDir {work}/spool/tmp
CacheDir {work}/cache
StateDir {work}/state
AccessLog {work}/logs/access
ErrorLog {work}/logs/error
PageLog {work}/logs/page
DataDir /usr/share/cups
""", encoding='utf-8')
    # Ubuntu's AppArmor profile is attached to /usr/sbin/cupsd by path and
    # would keep it out of this directory; a copy runs unconfined.
    cupsd = work / 'cupsd'
    shutil.copy(shutil.which('cupsd') or '/usr/sbin/cupsd', cupsd)
    log = open(work / 'logs/stdout', 'w', encoding='utf-8')
    server = subprocess.Popen(
        [cupsd, '-f', '-c', work / 'conf/cupsd.conf', '-s', work / 'conf/cups-files.conf'],
        stdout=log, stderr=subprocess.STDOUT)
    env = {'CUPS_SERVER': str(socket)}
    try:
        wait_until(socket.exists, 'the private CUPS server')
        run('lpadmin', '-p', QUEUE, '-E', '-v', 'file:///dev/null', '-m', 'raw',
            env={**os.environ, **env})
        listed = subprocess.run(['lpstat', '-e'], env={**os.environ, **env},
                                capture_output=True, text=True, check=True).stdout.split()
        if listed != [QUEUE]:
            raise SystemExit(f'The private server lists {listed}, not only {QUEUE}')
        yield env, lambda out: collect_spool_jobs(work / 'spool', out)
    finally:
        server.terminate()
        server.wait(timeout=20)
        log.close()
        socket.unlink(missing_ok=True)


@contextlib.contextmanager
def windows_queue(work):
    port = str(work / 'port.pdf')

    def powershell(script):
        run('powershell', '-NoProfile', '-Command',
            "$ErrorActionPreference = 'Stop'; " + script)

    powershell('Start-Service Spooler')
    powershell(f"Add-PrinterPort -Name '{port}'")
    powershell(f"Add-Printer -Name '{QUEUE}' -DriverName 'Microsoft Print To PDF' -PortName '{port}'")
    try:
        yield {'MEOW_PRINT_PORT_FILE': port}, lambda out: None
    finally:
        subprocess.run(['powershell', '-NoProfile', '-Command',
                        f"Remove-Printer -Name '{QUEUE}'; Remove-PrinterPort -Name '{port}'"])


@contextlib.contextmanager
def macos_queue(work):
    conf = '/etc/cups/cupsd.conf'
    files = '/etc/cups/cups-files.conf'
    run('sudo', 'sh', '-c', f'grep -q PreserveJobFiles {conf} || echo "PreserveJobFiles Yes" >> {conf}')
    run('sudo', 'sh', '-c', f'grep -q "^FileDevice" {files} || echo "FileDevice Yes" >> {files}')
    run('sudo', 'launchctl', 'kickstart', '-k', 'system/org.cups.cupsd')
    time.sleep(3)
    # macOS refuses raw queues. Its generic driver only filters at print time;
    # the spool keeps the document as the app submitted it.
    driver = next(Path('/System/Library/Frameworks/ApplicationServices.framework').rglob('Generic.ppd'), None)
    if driver is None:
        raise SystemExit('No generic printer driver (Generic.ppd) on this Mac')
    run('sudo', 'lpadmin', '-p', QUEUE, '-E', '-v', 'file:///dev/null', '-P', driver)
    spool = Path('/private/var/spool/cups')
    before = set(subprocess.run(['sudo', 'ls', spool], capture_output=True, text=True, check=True).stdout.split())

    def collect(out):
        names = subprocess.run(['sudo', 'ls', spool], capture_output=True, text=True, check=True).stdout.split()
        fresh = sorted(n for n in names if n.startswith('d') and n not in before)
        for index, name in enumerate(fresh):
            target = out / f'job-{index}.pdf'
            run('sudo', 'cp', spool / name, target)
            run('sudo', 'chmod', 'a+r', target)

    try:
        yield {}, collect
    finally:
        subprocess.run(['sudo', 'lpadmin', '-x', QUEUE])


def stand_in_queue(work):
    system = platform.system()
    if system == 'Linux':
        return linux_queue(work)
    if not os.environ.get('CI'):
        raise SystemExit(f'On {system} this changes the computer\'s printers, so it runs only in CI.')
    return windows_queue(work) if system == 'Windows' else macos_queue(work)


def headless(command):
    """Under Xvfb where it exists, so a CI run or a local one opens no window."""
    if platform.system() != 'Linux':
        return command
    wrapped = ['dbus-run-session', '--', *command]
    if shutil.which('xvfb-run'):
        wrapped = ['xvfb-run', '-a', '-s', '-screen 0 1440x1000x24', *wrapped]
    return wrapped


def check_spool(work, env, collect):
    out = work / 'out'
    out.mkdir()
    device = {'Linux': 'linux', 'Windows': 'windows', 'Darwin': 'macos'}[platform.system()]
    flutter = shutil.which('flutter')
    run(*headless([flutter, 'test', SPEC, '-d', device, '--reporter', 'expanded']), cwd=root,
        env={**os.environ, **env, 'MEOW_PRINT_QUEUE': QUEUE, 'MEOW_PRINT_OUT': str(out)})
    collect(out)
    manifest = json.loads((out / 'expected.json').read_text(encoding='utf-8'))
    jobs = sorted(out.glob('job-*.pdf'), key=lambda p: int(p.stem.split('-')[1]))
    issues = []
    if len(jobs) != len(manifest):
        issues.append(f'{len(jobs)} jobs reached the spooler, {len(manifest)} were sent')
    # Windows redraws through the print driver, which may turn text to outlines.
    require_text = platform.system() != 'Windows'
    for job, expected in zip(jobs, manifest):
        issues += job_issues(job, expected, require_text=require_text)
    evidence = root / 'artifacts/print-spool'
    evidence.mkdir(parents=True, exist_ok=True)
    for job in jobs:
        shutil.copy(job, evidence / job.name)
    if issues:
        raise SystemExit('\n'.join(issues))
    print(f'PASS: {len(jobs)} jobs reached the {platform.system()} spooler whole')


def check_flatpak(env):
    permissions = subprocess.run(['flatpak', 'info', '--show-permissions', FLATPAK_APP],
                                 capture_output=True, text=True, check=True).stdout
    if 'cups' not in permissions:
        raise SystemExit(f'The Flatpak has no CUPS socket:\n{permissions}')
    # Flatpak binds the host's server, named by CUPS_SERVER, at the usual path
    # inside the sandbox, where the private path itself does not exist.
    result = subprocess.run(headless(['flatpak', 'run', '--env=CUPS_SERVER=/run/cups/cups.sock',
                                      FLATPAK_APP, '--list-printers']),
                            env={**os.environ, **env}, capture_output=True, text=True, timeout=120)
    names = []
    for line in result.stdout.splitlines():
        with contextlib.suppress(json.JSONDecodeError, TypeError, KeyError):
            names.append(json.loads(line)['name'])
    if QUEUE not in names:
        raise SystemExit(f'The Flatpak does not see {QUEUE}; it lists {names}\n'
                         f'{result.stdout}\n{result.stderr}')
    print(f'PASS: the Flatpak sees the stand-in printer ({names})')


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--flatpak', action='store_true')
    arguments = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='meow-print-') as temporary:
        work = Path(temporary).resolve()
        with stand_in_queue(work) as (env, collect):
            if arguments.flatpak:
                check_flatpak(env)
            else:
                check_spool(work, env, collect)


if __name__ == '__main__':
    main()
