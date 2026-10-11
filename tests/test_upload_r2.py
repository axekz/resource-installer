import json
import os
import pathlib
import subprocess
import tempfile

# Linux CI tests use isolated fixtures and mock GitHub/R2; no network or credentials.
script = pathlib.Path(__file__).resolve().parents[1] / ".github/scripts/upload-r2.sh"
with tempfile.TemporaryDirectory() as d:
    p = pathlib.Path(d)
    gh = p / "gh"
    gh.write_text("""#!/usr/bin/env python3
import sys,os,json,pathlib,hashlib
a=sys.argv[1:]
if a[:2]==['release','view']: print(json.dumps({'isDraft':os.environ.get('DRAFT')=='1','isPrerelease':os.environ.get('PRERELEASE')=='1'}))
elif a[:2]==['release','download']:
 pathlib.Path('AXE-Resource-Installer.exe').write_bytes(b'fixture')
 digest=hashlib.sha256(b'fixture').hexdigest() if not os.environ.get('CORRUPT') else '0'*64
 pathlib.Path('SHA256SUMS.txt').write_text(digest+'  AXE-Resource-Installer.exe'+('\\r\\n' if os.environ.get('CRLF') else '\\n'))
elif a[0]=='api': print(os.environ.get('LATEST','v1.0.0'))
else: sys.exit(2)
""")
    aws = p / "aws"
    aws.write_text("""#!/usr/bin/env python3
import sys,os,json
with open(os.environ['UPLOAD_LOG'],'a') as f: f.write(json.dumps(sys.argv[1:])+'\\n')
if os.environ.get('FAIL_UPLOAD'): sys.exit(1)
""")
    gh.chmod(0o755)
    aws.chmod(0o755)
    base = dict(
        os.environ,
        PATH=str(p) + ":" + os.environ["PATH"],
        GH_TOKEN="fixture",
        GH_REPO="axekz/resource-installer",
        RELEASE_TAG="v1.0.0",
        R2_ACCOUNT_ID="fixture",
        R2_BUCKET_NAME="fixture",
        AWS_ACCESS_KEY_ID="fixture",
        AWS_SECRET_ACCESS_KEY="fixture",
        UPLOAD_LOG=str(p / "uploads"),
    )
    cases = [
        ("latest", {}, True, 4),
        ("Windows checksum", {"CRLF": "1"}, True, 4),
        ("older", {"LATEST": "v1.1.0"}, True, 2),
        ("draft", {"DRAFT": "1"}, False, 0),
        ("prerelease", {"PRERELEASE": "1"}, False, 0),
        ("checksum mismatch", {"CORRUPT": "1"}, False, 0),
        ("invalid tag", {"RELEASE_TAG": "../invalid"}, False, 0),
        ("missing credentials", {"AWS_SECRET_ACCESS_KEY": ""}, False, 0),
        ("upload failure", {"FAIL_UPLOAD": "1"}, False, 1),
    ]
    for name, extra, success, count in cases:
        log = p / "uploads"
        log.unlink(missing_ok=True)
        r = subprocess.run(
            ["bash", str(script)],
            env=dict(base, **extra),
            capture_output=True,
            text=True,
        )
        uploads = (
            [json.loads(line) for line in log.read_text().splitlines()]
            if log.exists()
            else []
        )
        assert (r.returncode == 0) == success, (name, r.stderr)
        assert len(uploads) == count, (name, uploads)
        if name == "latest":
            assert (
                uploads[0][3]
                == "s3://fixture/packages/resource-installer/v1.0.0/AXE-Resource-Installer.exe"
            )
            assert uploads[2][3] == "s3://fixture/packages/AXE-Resource-Installer.exe"
            assert "public, max-age=300, must-revalidate" in uploads[2]
            assert 'attachment; filename="AXE-Resource-Installer.exe"' in uploads[2]
        print("PASS:", name)
