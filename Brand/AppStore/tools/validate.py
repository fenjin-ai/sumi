#!/usr/bin/env python3
"""Validate storefront text lengths, authentic sources, PNG format, and reel media."""
from pathlib import Path
import json, struct, subprocess
ROOT=Path(__file__).resolve().parents[1]
LIMITS={'name':30,'subtitle':30,'keywords':100,'promotional_text':170,'description':4000}
for lang in ('zh-Hans','en-US'):
 data=json.loads((ROOT/'metadata'/lang/'fields.json').read_text())
 for key,limit in LIMITS.items():
  assert len(data[key])<=limit,(lang,key,len(data[key]),limit)
  assert (ROOT/'metadata'/lang/(key+'.txt')).read_text().rstrip('\n')==data[key]
  print(f'{lang} {key}: {len(data[key])}/{limit}')
 assert len(data['keywords'].encode('utf-8'))<=100
 manifest=[m for m in json.loads((ROOT/'manifest.json').read_text()) if m['locale']==lang]
 assert len(manifest)==8
 for item in manifest:
  p=ROOT/item['file']; raw=p.read_bytes()
  assert raw[:8]==b'\x89PNG\r\n\x1a\n',p
  width,height,depth,color=struct.unpack('>IIBB',raw[16:26])
  assert (width,height,depth,color)==(2880,1800,8,2),(p,width,height,depth,color)
  assert (ROOT/item['source']).read_bytes()[:2]==b'\xff\xd8',item['source']
  assert p.with_suffix('.svg').exists()
 video=ROOT/'video'/('marketing-reel.'+lang+'.mp4')
 probe=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-show_format','-of','json',str(video)],text=True))
 stream=next(s for s in probe['streams'] if s['codec_type']=='video')
 assert (stream['codec_name'],stream['width'],stream['height'],stream['r_frame_rate'],stream['pix_fmt'])==('h264',1920,1080,'30/1','yuv420p')
 assert abs(float(probe['format']['duration'])-24)<0.1
 assert len(probe['streams'])==1,'Marketing reels intentionally have no audio.'
 print(f'{lang}: 8 RGB screenshots, matching SVG/JPEG sources, and a 24-second H.264 reel verified.')
