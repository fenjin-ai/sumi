#!/usr/bin/env python3
"""Make a silent 24-second marketing reel; this is not an App Preview recording."""
from pathlib import Path
import importlib.util, subprocess
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('artwork',ROOT/'tools/render.py')
artwork=importlib.util.module_from_spec(spec); spec.loader.exec_module(artwork)
# All intermediate encodes remain in this SSD-backed checkout's ignored build folder.
repo=ROOT.parents[1]
work=repo/'build/store-video'; work.mkdir(parents=True,exist_ok=True)
for lang in artwork.COPY:
 clips=[]
 for i,name in enumerate(artwork.FILES):
  clip=work/(lang+'-'+name+'.mp4'); clips.append(clip)
  color=artwork.PALETTES[i][0]
  filters=(f'scale=1728:1080,pad=1920:1080:96:0:color={color},'
           "zoompan=z='1+0.025*on/89':x='iw/2-iw/zoom/2':y='ih/2-ih/zoom/2':d=90:s=1920x1080:fps=30,"
           'fade=t=in:st=0:d=0.25,fade=t=out:st=2.75:d=0.25,format=yuv420p')
  subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-i',str(ROOT/'screenshots'/lang/(name+'.png')),
                  '-vf',filters,'-t','3','-an','-c:v','libx264','-crf','18','-preset','medium',str(clip)],check=True)
 listing=work/(lang+'.txt'); listing.write_text(''.join("file '"+str(p)+"'\n" for p in clips))
 output=ROOT/'video'/('marketing-reel.'+lang+'.mp4')
 subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-f','concat','-safe','0','-i',str(listing),
                 '-c','copy','-movflags','+faststart',str(output)],check=True)
 print(output.relative_to(ROOT))
