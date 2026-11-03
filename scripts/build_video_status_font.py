"""Generate the native dual-port BRAM OSD font from its retained golden function."""
import argparse
from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
source=(ROOT/'fpga/user_source/hdl_source/video_effects_osd.v').read_text(encoding='utf-8')
f=source[source.index('function [15:0] font_row;'):]
f=f[:f.index('endfunction')+len('endfunction')]
d=source[source.index('function [15:0] double_bits;'):]
d=d[:d.index('endfunction')+len('endfunction')]
chinese={int(k,16):int(v,16) for k,v in re.findall(r"8'h([0-9A-F]{2}): glyph = 256'h([0-9A-F]+)",f)}
ascii_glyphs={ord(k):int(v,16) for k,v in re.findall(r'"(.)": ascii_glyph = 64\x27h([0-9A-F]+)',f)}
assert sorted(chinese)==list(range(128,max(chinese)+1))
assert len(chinese)<=96 and 15<len(ascii_glyphs)<31
mapping={code:i+1 for i,code in enumerate(sorted(ascii_glyphs))}
rows=[0]*2048
for code,glyph in chinese.items():
    for row in range(16): rows[(code-0x60)*16+row]=(glyph>>((15-row)*16))&65535
for code,glyph in ascii_glyphs.items():
    for row in range(16):
        byte=(glyph>>((7-row//2)*8))&255
        rows[mapping[code]*16+row]=int(''.join(bit*2 for bit in f'{byte:08b}'),2)
lines=['// Generated from the retained OSD font_row golden function. Do not hand edit.',
'module video_status_font(input wire clk, input wire enable_a, enable_b, input wire [7:0] code_a, code_b,',
'    input wire [3:0] row_a, row_b, output wire [15:0] data_a, data_b);',
'function [6:0] glyph_index; input [7:0] code; begin',
f"    if (code>=8'h80 && code<=8'h{max(chinese):02x}) glyph_index=code-8'h60;",
'    else case(code)']
lines += [f"        8'h{k:02x}: glyph_index=7'd{v};" for k,v in mapping.items()]
lines += ["        default: glyph_index=0; endcase end endfunction",
'wire [10:0] address_a={glyph_index(code_a),row_a};',
'wire [10:0] address_b={glyph_index(code_b),row_b};',
'reg bank_a,bank_b;',
'always @(posedge clk) begin if(enable_a) bank_a<=address_a[10]; if(enable_b) bank_b<=address_b[10]; end']
for bank in range(2):
    for lane in range(2):
        ident=f'b{bank}_l{lane}'
        values=[(v>>(lane*8))&255 for v in rows[bank*1024:(bank+1)*1024]]
        lines += [f'wire [8:0] a_{ident},b_{ident};','EG_PHY_BRAM #(',
'    .MODE("DP8K"), .DATA_WIDTH_A("9"), .DATA_WIDTH_B("9"),',
'    .REGMODE_A("NOREG"), .REGMODE_B("NOREG"), .GSR("DISABLE"),',
'    .CEAMUX("SIG"), .CEBMUX("SIG"), .OCEAMUX("1"), .OCEBMUX("1"),',
'    .WEAMUX("0"), .WEBMUX("0"),',
'    .CSA0("1"), .CSA1("1"), .CSA2("1"),',
'    .CSB0("1"), .CSB1("1"), .CSB2("1"),']
        for n in range(32):
            value=sum(v<<(8*i) for i,v in enumerate(values[n*32:(n+1)*32]))
            lines.append(f"    .INIT_{n:02X}(256'h{value:064X})"+(',' if n<31 else ''))
        lines += [f') {ident} (',
"    .addra({address_a[9:0],3'b111}), .addrb({address_b[9:0],3'b111}),",
"    .dia(9'd0), .dib(9'd0), .clka(clk), .clkb(clk),",
f"    .cea(enable_a && address_a[10]==1'b{bank}), .ceb(enable_b && address_b[10]==1'b{bank}), .ocea(1'b1), .oceb(1'b1),",
"    .wea(1'b0), .web(1'b0), .csa(3'b111), .csb(3'b111),",
f"    .rsta(1'b0), .rstb(1'b0), .doa(a_{ident}), .dob(b_{ident}));"]
lines += ["assign data_a=bank_a ? {a_b1_l1[7:0],a_b1_l0[7:0]} : {a_b0_l1[7:0],a_b0_l0[7:0]};",
"assign data_b=bank_b ? {b_b1_l1[7:0],b_b1_l0[7:0]} : {b_b0_l1[7:0],b_b0_l0[7:0]};",'endmodule']
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--check',action='store_true')
args=parser.parse_args()
output=ROOT/'fpga/user_source/hdl_source/video_status_font.v'
content='\n'.join(lines)+'\n'
if args.check:
    assert output.read_text(encoding='utf-8')==content,'OSD font generation differs'
    print('GENERATOR_PASS status font deterministic')
else:
    output.write_text(content,encoding='utf-8')
    print('GENERATED',output)
