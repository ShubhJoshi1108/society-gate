"""Run after `flutter create --platforms=android .` to apply Society Gate's Android settings."""
import re
from pathlib import Path

manifest = Path("android/app/src/main/AndroidManifest.xml")
xml = manifest.read_text()

perms = """    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.CAMERA"/>
"""
if "android.permission.INTERNET" not in xml:
    xml = re.sub(r"(<manifest[^>]*>\s*)", lambda m: m.group(1) + perms, xml, count=1)

xml = re.sub(r'android:label="[^"]*"', 'android:label="Society Gate"', xml, count=1)

queries = """    <queries>
        <intent><action android:name="android.intent.action.DIAL"/><data android:scheme="tel"/></intent>
        <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="https"/></intent>
        <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="ntfy"/></intent>
        <intent><action android:name="android.media.action.IMAGE_CAPTURE"/></intent>
"""
if "<queries>" in xml:
    xml = xml.replace("    <queries>\n", queries, 1)
else:
    xml = xml.replace("</manifest>", queries + "    </queries>\n</manifest>")

# Allow plain http only for local testing servers (e.g. http://192.168.x.x:8090)
xml = xml.replace("<application", '<application\n        android:usesCleartextTraffic="true"', 1)

manifest.write_text(xml)
print("AndroidManifest.xml patched")
