"""A tiny original SWF fixture: blue stage, green rectangle; no third-party game assets."""
from pathlib import Path
import struct
import base64

root = Path(__file__).resolve().parents[1]
def bits(fields):
    text = ''.join(format(value & ((1 << count) - 1), f'0{count}b') for value, count in fields)
    text += '0' * (-len(text) % 8)
    return int(text, 2).to_bytes(len(text) // 8, 'big')

def rect(x0, x1, y0, y1):
    width = max(abs(v).bit_length() + 1 for v in [x0,x1,y0,y1])
    return bits([(width,5)] + [(v,width) for v in [x0,x1,y0,y1]])

def tag(code, data=b''):
    return struct.pack('<H', (code << 6) | min(len(data),63)) + (struct.pack('<I',len(data)) if len(data)>=63 else b'') + data

# DefineShape with a single solid green rectangular fill.
shape = struct.pack('<H',1) + rect(0,2000,0,2000) + bytes([1,0,60,220,120,0])
records = [(1,4),(0,4), (0,1),(5,5),(1,5),(0,1),(0,1),(1,1)]
for delta, vertical in [(2000,0),(2000,1),(-2000,0),(-2000,1)]:
    records += [(1,1),(1,1),(10,4),(0,1),(vertical,1),(delta,12)]
records += [(0,1),(0,5)]
shape += bits(records)
matrix = bits([(0,1),(0,1),(12,5),(1200,12),(1200,12)])
def action(code, payload=b''):
    return bytes([code]) + (struct.pack('<H',len(payload)) if code >= 128 else b'') + payload
def push(*values):
    return action(0x96,b''.join(b'\x00'+v.encode()+b'\x00' if isinstance(v,str) else b'\x07'+struct.pack('<i',v) for v in values))
left = push('/box',0,60) + action(0x23)
right = push('/box',0,180) + action(0x23)
# Each frame: box._x = Key.isDown(68 /* D */) ? 180 : 60.
check = push(68,1,'Key') + action(0x1c) + push('isDown') + action(0x52)
jump = action(0x99,struct.pack('<h',len(right)))
actions = check + action(0x9d,struct.pack('<h',len(left)+len(jump))) + left + jump + right + b'\x00'
body = rect(0,6400,0,4800) + struct.pack('<HH',24*256,2)
body += tag(9,bytes([20,40,70])) + tag(2,shape)
sprite = struct.pack('<HH',2,1) + tag(4,struct.pack('<HH',1,1)+b'\x00') + tag(1) + tag(0)
body += tag(39,sprite) + tag(26,bytes([0x26])+struct.pack('<HH',1,2)+matrix+b'box\x00')
body += tag(12,actions)+tag(1)+tag(12,actions)+tag(1)+tag(0)
swf = b'FWS' + bytes([7]) + struct.pack('<I',8+len(body)) + body
(root/'tests'/'smoke.swf').write_bytes(swf)
encoded = base64.b64encode(swf).decode()
html = f'''<!doctype html><html lang="zh-CN"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>本地播放器自检</title>
<style>body{{background:#101827;color:#eee;font:18px system-ui;padding:32px}}object{{display:block;width:640px;max-width:90vw;height:480px}}input{{font:inherit}}a{{color:#80caff}}</style>
<h1>本地 Flash 播放器自检</h1>
<p>正常结果：下方出现深蓝色舞台和绿色方块。点击舞台后，按住 D 方块右移，松开恢复。</p>
<object type="application/x-shockwave-flash" data="data:application/x-shockwave-flash;base64,{encoded}" width="640" height="480"></object>
<p>这是自制渲染样例，不代表 4399 游戏已经通过兼容性测试。</p>
<p><input placeholder="验证网页文字输入仍然正常"></p>
<p><a href="https://www.4399.com/">返回 4399</a> · 三指轻点打开菜单</p>
</html>'''
(root/'Flash4399'/'WebAssets'/'selftest.html').write_text(html,encoding='utf8')
print('Created original SWF fixture and offline self-test page')
