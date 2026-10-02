#!/usr/bin/env python3
"""Render App Store artwork from authentic captures with librsvg and ImageMagick."""
from pathlib import Path
import base64, html, json, subprocess
ROOT = Path(__file__).resolve().parents[1]
W, H = 2880, 1800
PALETTES = [('#F4F4EF','#24282D','#69766E'),('#24282D','#ECECE7','#B9C8BE'),('#E4EBE4','#253238','#62746B'),('#24282D','#ECECE7','#B9C8BE'),('#F4F4EF','#24282D','#69766E'),('#F4F4EF','#24282D','#69766E'),('#F4F4EF','#24282D','#69766E'),('#24282D','#ECECE7','#B9C8BE')]
COPY = {
 'zh-Hans': [
  ('文章与随笔',['让想法落笔，','让页面成形。'],['从第一句话，到值得分享的成稿。','专注写作，实时看见排版。'],'专注写作  /  并排预览'),
  ('技术与学习',['把复杂的想法讲清楚。'],['正文、公式与代码，在同一页里相遇。'],'公式  /  代码  /  表格'),
  ('工作与研究',['把思路写成一份好报告。'],['让结构清楚，让细节有据可查。'],'章节  /  表格  /  交叉引用'),
  ('演示与教学',['给下一次演讲，一个好开场。'],['用 16:9 演示页，让想法被更多人看见。'],'演示页  /  讲义  /  PDF'),
  ('图解与关系',['让关系，有形可见。'],['画一张矢量图，把过程与正文放在一起。'],'矢量图解  /  流程  /  说明'),
  ('海报与版式',['页面，也是一种','表达方式。'],['试试色彩、几何与文字的组合。','做一页海报，或下一本刊物的封面。'],'视觉海报  /  封面  /  PDF'),
  ('工具与发现',['想用的工具，就在手边。'],['按下 ⌘J，从标题、公式到纸张设置。'],'发现命令  /  键盘操作'),
  ('长文与手稿',['长文，也能从容展开。'],['沿着大纲穿过章节，回到需要修改的地方。'],'文章脉络  /  自动保存  /  版本历史'),
 ],
 'en-US': [
  ('ESSAYS & IDEAS',['Room to think.','Pages to share.'],['From the first sentence to a finished page.','Focused writing. Live typesetting.'],'FOCUSED WRITING  /  LIVE PREVIEW'),
  ('NOTES & REASONING',['Make the complex clear.'],['Prose, equations, and code. One thoughtful page.'],'EQUATIONS  /  CODE  /  TABLES'),
  ('REPORTS & RESEARCH',['Give your thinking structure.'],['A clear argument. Details that are easy to follow.'],'HEADINGS  /  TABLES  /  REFERENCES'),
  ('PRESENTATIONS & TEACHING',['Give your next talk a clear start.'],['Build a 16:9 presentation. Give an idea a wider audience.'],'SLIDE LAYOUTS  /  HANDOUTS  /  PDF'),
  ('DIAGRAMS & CONNECTIONS',['See how the pieces connect.'],['Draw a vector diagram. Keep the explanation beside it.'],'VECTOR DIAGRAMS  /  FLOW  /  EXPLANATION'),
  ('POSTERS & PAGE DESIGN',['A page can be','an expression.'],['Explore color, geometry, and type.','Make a poster or the cover of your next journal.'],'POSTERS  /  COVERS  /  PDF'),
  ('TOOLS & DISCOVERY',['The next tool is close at hand.'],['Press ⌘J. Discover headings, equations, page settings, and more.'],'COMMAND DISCOVERY  /  KEYBOARD WORKFLOW'),
  ('LONG FORM & MANUSCRIPTS',['Keep the whole story in view.'],['Follow the outline. Find the next passage to revise.'],'OUTLINE  /  AUTOSAVE  /  HISTORY'),
 ]
}
FILES=['01-essay','02-notes','03-report','04-slides','05-diagram','06-poster','07-commands','08-manuscript']
def uri(path,mime): return 'data:'+mime+';base64,'+base64.b64encode(path.read_bytes()).decode()
def text(x,y,value,size,fill,font='sans-serif',spacing=None):
 return f'<text x="{x}" y="{y}" font-family="{font}" font-size="{size}" fill="{fill}"'+(f' letter-spacing="{spacing}"' if spacing else '')+'>'+html.escape(value)+'</text>'
def image(path,x,y,w,h,mime='image/jpeg'):
 return f'<image x="{x}" y="{y}" width="{w}" height="{h}" href="{uri(path,mime)}"/>'
def render(lang,i):
 bg,fg,muted=PALETTES[i]; eyebrow,headline,body,features=COPY[lang][i]; chinese=lang=='zh-Hans'
 serif='Songti SC' if chinese else 'Georgia'; sans='PingFang SC' if chinese else 'Helvetica Neue'
 raw=ROOT/'raw'/lang/(FILES[i]+'.jpg')
 dimensions=subprocess.check_output(['magick','identify','-format','%w %h',str(raw)],text=True).split(); ratio=int(dimensions[1])/int(dimensions[0])
 out=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',f'<rect width="{W}" height="{H}" fill="{bg}"/>']
 mark=ROOT.parent/('mark-light.svg' if i in (1,3,7) else 'mark-dark.svg')
 out += [image(mark,140,100,62,62,'image/svg+xml'),text(228,145,'留白' if chinese else 'LeftBlank',42,fg,sans),text(2740,145,f'0{i+1} / 08',28,muted,sans)]
 out += [f'<path d="M140 195H2740" stroke="{muted}" stroke-opacity=".35"/>']
 if i in (0,5):
  out += [text(140,350,eyebrow,30,muted,sans,3)]
  for j,line in enumerate(headline): out += [text(140,560+j*145,line,103 if chinese else 104,fg,serif)]
  for j,line in enumerate(body): out += [text(145,910+j*58,line,30 if not chinese and i==5 else 32,muted,sans)]
  sx,sy,sw=900,340,1840; sh=sw*ratio
  if i == 5: sx,sy,sw,sh=1510,300,1160,1269
  out += [f'<rect x="{sx-20}" y="{sy-20}" width="{sw+40}" height="{sh+40}" rx="28" fill="{muted}" opacity=".13"/>']
  if i == 5:
   # A genuine detail crop of the preview pane, with its actual toolbar.
   rw,rh=map(int,dimensions)
   out += [f'<svg x="{sx}" y="{sy}" width="{sw}" height="{sh}" viewBox="{rw/2} 0 {rw/2} {rh}" preserveAspectRatio="xMidYMid meet">',image(raw,0,0,rw,rh),'</svg>']
  else: out += [image(raw,sx,sy,sw,sh)]
  out += [text(sx,sy+sh+96,'文字与成稿，同一个工作空间。' if chinese and i==0 else ('Read it as your reader will.' if i==5 and not chinese else ('用实际排版结果，检查每一页。' if chinese else 'Your words and the page, together.')),30,muted,sans)]
  out += [text(140,1455,'此中有真意，欲辨已忘言' if chinese else 'Ink for your thoughts',32,muted,serif)]
 else:
  out += [text(140,280,eyebrow,27,muted,sans,3)]
  out += [text(140,405,headline[0],104 if chinese else 91,fg,serif)]
  out += [text(145,485,body[0],34,muted,sans)]
  sx,sy,sw=235,555,2410; sh=sw*ratio
  out += [f'<rect x="{sx-18}" y="{sy-18}" width="{sw+36}" height="{sh+36}" rx="25" fill="{muted}" opacity=".16"/>',image(raw,sx,sy,sw,sh)]
 # Footer lives over the opaque canvas and stays separate from the authentic interface.
 out += [f'<rect y="{H-115}" width="{W}" height="115" fill="{bg}"/>',f'<path d="M140 {H-115}H2740" stroke="{muted}" stroke-opacity=".35"/>',text(145,H-49,features,28,muted,sans),text(2450,H-49,'MADE FOR MAC',25,muted,sans,2),'</svg>']
 folder=ROOT/'screenshots'/lang; folder.mkdir(exist_ok=True,parents=True)
 svg=folder/(FILES[i]+'.svg'); svg.write_text('\n'.join(out))
 png=svg.with_suffix('.png')
 subprocess.run(['rsvg-convert',str(svg),'-o',str(png)],check=True)
 subprocess.run(['magick',str(png),'-background',bg,'-alpha','remove','-alpha','off','PNG24:'+str(png)],check=True)
 return png

def main():
 manifest=[]
 for lang in COPY:
  for i in range(8):
   png=render(lang,i); manifest.append(dict(locale=lang,order=i+1,file=str(png.relative_to(ROOT)),headline=COPY[lang][i][1],source=str((ROOT/'raw'/lang/(FILES[i]+'.jpg')).relative_to(ROOT))))
 (ROOT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
 for lang in COPY:
  subprocess.run(['magick','montage','-font','/System/Library/Fonts/Supplemental/Arial.ttf',*[str(ROOT/'screenshots'/lang/(n+'.png')) for n in FILES],'-thumbnail','720x450','-tile','4x2','-geometry','+16+16','-background','#D7D9D3',str(ROOT/('contact-sheet.'+lang+'.jpg'))],check=True)
 print('Rendered 16 opaque 2880 × 1800 PNGs and editable SVGs.')
if __name__=='__main__': main()
