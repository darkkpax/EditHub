from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
root=Path('desktop')
font_path=root/'src/assets/fonts/UnifrakturCook-Bold.ttf'
size=800
while True:
 font=ImageFont.truetype(str(font_path),size)
 box=font.getbbox('EH')
 if box[2]-box[0]<=800 and box[3]-box[1]<=680:break
 size-=1
image=Image.new('RGBA',(1024,1024),(0,0,0,0))
draw=ImageDraw.Draw(image)
draw.rounded_rectangle((0,0,1023,1023),radius=210,fill='#080808')
x=(1024-(box[2]-box[0]))/2-box[0]
y=(1024-(box[3]-box[1]))/2-box[1]-10
draw.text((x,y),'EH',font=font,fill='#f2f0ed')
icons=root/'src-tauri/icons'
image.save(icons/'icon.png')
image.save(icons/'icon.ico',sizes=[(16,16),(20,20),(24,24),(32,32),(40,40),(48,48),(64,64),(128,128),(256,256)])
tt=TTFont(font_path)
glyphs=tt.getGlyphSet();cmap=tt.getBestCmap();units=tt['head'].unitsPerEm
paths=[];advance=0
for letter in 'EH':
 name=cmap[ord(letter)];pen=SVGPathPen(glyphs);glyphs[name].draw(TransformPen(pen,(1,0,0,1,advance,0)));paths.append(pen.getCommands());advance+=tt['hmtx'][name][0]
# Preserve the same font coordinates and baseline used by the raster icon.
scale=size/units
svg=f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024"><rect width="1024" height="1024" rx="210" fill="#080808"/><g fill="#f2f0ed" transform="translate({x} {y+font.getmetrics()[0]}) scale({scale} {-scale})">'+''.join(f'<path d="{p}"/>' for p in paths)+'</g></svg>'
(icons/'icon.svg').write_text(svg,encoding='utf-8')
print('generated EH icon: 1024 PNG, multi-size ICO, outlined SVG')
