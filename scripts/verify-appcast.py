"""Check the signed feed describes the exact archive being published."""

import plistlib
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def verify(feed, archive, app, tools, account, download_url):
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    ns = {'sparkle': 'http://www.andymatuschak.org/xml-namespaces/sparkle'}
    items = ET.parse(feed).findall('./channel/item')
    if len(items) != 1:
        raise ValueError('Expected exactly one update in the release feed.')
    item = items[0]
    enclosure = item.find('enclosure')
    if enclosure is None:
        raise ValueError('Missing update archive.')
    signature = enclosure.get(f"{{{ns['sparkle']}}}edSignature")
    if (item.findtext('sparkle:version', namespaces=ns) != info['CFBundleVersion']
            or item.findtext('sparkle:shortVersionString', namespaces=ns) != info['CFBundleShortVersionString']
            or enclosure.get('url') != download_url
            or enclosure.get('length') != str(archive.stat().st_size)
            or not signature):
        raise ValueError('Update feed metadata does not match the release archive.')
    subprocess.run([str(tools / 'sign_update'), '--account', account,
                    '--verify', str(archive), signature], check=True)
    subprocess.run([str(tools / 'sign_update'), '--account', account,
                    '--verify', str(feed)], check=True)


if __name__ == '__main__':
    verify(*(Path(value) for value in sys.argv[1:5]), *sys.argv[5:7])
