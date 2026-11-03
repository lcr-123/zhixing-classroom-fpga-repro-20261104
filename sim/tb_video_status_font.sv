`timescale 1ns/1ps
module tb_video_status_font;
reg clk=0; always #20 clk=~clk;
reg [7:0] ca=0,cb=0; reg [3:0] ra=0,rb=0;
reg ena=1,enb=1;
wire [15:0] da,db;
video_status_font dut(.clk(clk),.enable_a(ena),.enable_b(enb),.code_a(ca),.code_b(cb),.row_a(ra),.row_b(rb),.data_a(da),.data_b(db));
function [15:0] double_bits;
    input [7:0] bits;
    begin
        double_bits = {{2{bits[7]}}, {2{bits[6]}},
                       {2{bits[5]}}, {2{bits[4]}},
                       {2{bits[3]}}, {2{bits[2]}},
                       {2{bits[1]}}, {2{bits[0]}}};
    end
endfunction
function [15:0] font_row;
    input [7:0] char_code;
    input [3:0] row;
    reg [255:0] glyph;
    reg [63:0] ascii_glyph;
    begin
        glyph = 256'd0;
        ascii_glyph = 64'd0;
        case (char_code)
            8'h80: glyph = 256'h00007FFC200C220C27CC2E4C2B8C23CC2D3C218C220C218C200C7FFC60000000; // 图
            8'h81: glyph = 256'h198013F036203FF8724853F8518016D81170167015A8162434C0008000000000; // 像
            8'h82: glyph = 256'h020002003FF8101810181FF8101810181FF8101810181FF83018000000000000; // 自
            8'h83: glyph = 256'h002000207E2001FC00247E2410241064224422447FC400840118000000000000; // 动
            8'h84: glyph = 256'h000020083FF804600460046004607FFC046004600C6008601860706000000000; // 开
            8'h85: glyph = 256'h0860044004403FF80100010001007FFC0180028006601838701C000000000000; // 关
            8'h86: glyph = 256'h01007FFC00001FF018301FF000007FFC400407C004400C44387C200000000000; // 亮
            8'h87: glyph = 256'h01803FF8200022202FF8222023E020002FF02220214040804F7C100400000000; // 度
            8'h88: glyph = 256'h001800107E1005FC04102410159018900CD01410321062104030000000000000; // 对
            8'h89: glyph = 256'h0000208020802080209C20B03EC020802080208022802C84708C20F800000000; // 比
            8'h8A: glyph = 256'h08400858484868402BFC08401860186028A048B0099009080E0C000000000000; // 状
            8'h8B: glyph = 256'h030002007FFC06C004400A20311C600001002498240C443447E0000000000000; // 态
            8'h8C: glyph = 256'h000000003FF8010001000100110011F8110011001100110011007FFC00000000; // 正
            8'h8D: glyph = 256'h030002007FFC040004401840184033F8704050401040104017FC100000000000; // 在
            8'h8E: glyph = 256'h0000100011F011107D10111031103D1035105110511011101214161C00000000; // 机
            8'h8F: glyph = 256'h104010C010A07D1013EC37E438007E48535851701110102017FC000000000000; // 检
            8'h90: glyph = 256'h204033FC184003F8004077FC33F8320833F832083BF832080218000000000000; // 请
            8'h91: glyph = 256'h0240224013F80440004077FC10A011A01120132416383C0043FC000000000000; // 选
            8'h92: glyph = 256'h13F8111810907CE010E0131C384073F81040104017FC10407040004000000000; // 择
            8'h93: glyph = 256'h004000407C4011FC10441044104C104C10881E88618803080638000000000000; // 功
            8'h94: glyph = 256'h1840105826706F40504400783E4022483E7822403E402244267C000000000000; // 能
            8'h95: glyph = 256'h1040106013FC7A04124410C01BFC3098511013B0106010F8770C000000000000; // 按
            8'h96: glyph = 256'h302027F87A2842FC0A283778252079F8252026FC2A20332024FC000000000000; // 键
            8'h97: glyph = 256'h0000100013FC104410443C447044104C10CC14881C8831080308063800000000; // 切
            8'h98: glyph = 256'h1080110011F07A2017F812481A48324857FC106010A01118760C000000000000; // 换
            8'h99: glyph = 256'h0310313010207FFC400440041FE000C001007FFC010001000700020000000000; // 学
            8'h9A: glyph = 256'h00001FF8000808080E1803180018005801D80E181818001000F0000000000000; // 习
            8'h9B: glyph = 256'h10401040104010401FFC100010001FE010201020302020206020000000000000; // 片
            8'h9C: glyph = 256'h30C020A0793023FC260453CC7A5853D812581BD87258127812D8100000000000; // 输
            8'h9D: glyph = 256'h04000600030001000180028002C006400C6008301018600C4000000000000000; // 入
            8'h9E: glyph = 256'h10403F7C28904508030004C0187077DC40001FF018301FF01830000000000000; // 答
            8'h9F: glyph = 256'h01003FF8220804003FF80C4003E03E1801003FFC05401930610C000000000000; // 案
            8'hA0: glyph = 256'h0000010001007FFC05400930311C5FF410101FF010101FF000007FFC00000000; // 查
            8'hA1: glyph = 256'h03F83F001FF802007FFC04000FF818183FF848180FF808180FF8081800000000; // 看
            8'hA2: glyph = 256'h1020102023FC6420782059FC100021F87D08010801087DF80108000000000000; // 结
            8'hA3: glyph = 256'h00001FF0111011101FF011101FF001007FFC07400D601930710C010000000000; // 果
            8'hA4: glyph = 256'h0000002032A422AC4AE87A2052FC322022787A6802A402A07A0003FC00000000; // 继
            8'hA5: glyph = 256'h106033FC20406BFC480C71A810A02320792003FC004078D8070C000000000000; // 续
            8'hA6: glyph = 256'h000000303FC001007FFC01001FF011101FF01FF001003FF801007FFC00000000; // 重
            8'hA7: glyph = 256'h083C7F4000402640047C7F4808487F4808483A486AC848881988000800000000; // 新
            8'hA8: glyph = 256'h00003FF82008200827C824482448244827C8200820083FF82008000000000000; // 回
            8'hA9: glyph = 256'h109030903BFC609040903BFC10007DF8110811F81D08190811F8000000000000; // 错
            8'hAA: glyph = 256'h00007DFC24203C2024F824887CA87EA808A868A84E5068D8588047FC00000000; // 题
            8'hAB: glyph = 256'h0000000013FC126402F47244124412F4120412F41A9412F404040C1C00100000; // 调
            8'hAC: glyph = 256'h044004407FFC044004407FF80208020802080208027802000200000000000000; // 节
            8'hAD: glyph = 256'h01007FFC01003FF800001FF81108110811083FF8200020006000000000000000; // 声
            8'hAE: glyph = 256'h01003FF800000C6004407FFC00001FF010101FF0101010101FF0000000000000; // 音
            8'hAF: glyph = 256'h2120212017FC01200120712017FC1120112012201620780047FC000000000000; // 进
            8'hB0: glyph = 256'h00187DE045004500450045FC451045107D104510421006100410000000000000; // 听
            8'hB1: glyph = 256'h10A010A014AC7AA812B810A018B073B814A8112011241324763C000000000000; // 挑
            8'hB2: glyph = 256'h1080109010901E8C11F812807C584450447044607C6445B4031C000000000000; // 战
            8'hB3: glyph = 256'h00007FFC044004403FF824483FF802000200FFFC08400F8003F07C1C00000000; // 要
            8'hB4: glyph = 256'h108010F831902B50686069DC2B2428C029182860299C207023C0020000000000; // 修
            8'hB5: glyph = 256'h00407CC0048004FC051005103C902090206020602C607198670C040400000000; // 改
            8'hB6: glyph = 256'h0840104010FC7EFC6284630462447E44626C620862087E086238000000000000; // 的
            8'hB7: glyph = 256'h0300064008201FF002007FFC08A033184CEC03901E7001C03E00000000000000; // 参
            8'hB8: glyph = 256'h000008602A4008407F7C18886A8841487F50125022301E200B58718C01000000; // 数
            8'hB9: glyph = 256'h00B0009800803FFC208020C83E5822502270226026646DB4431C000000000000; // 成
            8'hBA: glyph = 256'h304023FC20404BF8784017FC20007BF86348034878404098070C040000000000; // 绩
            8'hBB: glyph = 256'h0C000FF810007FF018101FF0181007E00FF01C20364001807E7C000000000000; // 复
            8'hBC: glyph = 256'h00783F80030004701FC0030004303FFC018401801998218C4300000000000000; // 系
            8'hBD: glyph = 256'h1040104023FC6CC07880111813FC23A07CA000A005A07924423C000000000000; // 统
            8'hBE: glyph = 256'h00001FF0101010101FF0100C1FF8000004207FFC042008201820702000000000; // 异
            8'hBF: glyph = 256'h111009207FFC40045FF4101010101FF001003FF8210821082130010000000000; // 常
            8'hC0: glyph = 256'h106023FC22044B80597C73102720275C7B44037C03447B44037C034400000000; // 缩
            8'hC1: glyph = 256'h1060184000407EFC108811881E58125032502230222066584D8C000000000000; // 放
            8'hC2: glyph = 256'h10401020102011FEFD021102110215FE19023100D10011001200120054002800; // 护
            8'hC3: glyph = 256'h03F87A084A084BF87A084A084BF87A444A484A304A207A104A88030602000000; // 眼
            8'hC4: glyph = 256'h000001807FFC08100420FFFE00003FF8200820083FF8200820083FF820080000; // 音
            8'hC5: glyph = 256'h00001FF810081FF810081FF800007FFE10881FF810883FFC00807FFE00000000; // 量
            8'hC6: glyph = 256'h41102110311017FC01100110E1102FFE21102110231022106410D0008FFE0000; // 进
            8'hC7: glyph = 256'h7EFE402040405EFC5284529452945A945494509452A454305848508483020000; // 顾
            8'hC8: glyph = 256'h3FF002000200020002007FFC0480048004800880088010842084407C80000000; // 无
            8'hC9: glyph = 256'h10100820FFFE020004003FF8200820083FF8200820083FF8200820083FF82008; // 首
            8'hCA: glyph = 256'h7FFC020004001FF0101011101110111011101110129002400420181060080000; // 页
            8'hCB: glyph = 256'h0008203C13C01200020003FCF204128812501220125014881504280047FE0000; // 返
            default: glyph = 256'd0;
        endcase

        case (char_code)
            "0": ascii_glyph = 64'h3C666E7666663C00;
            "1": ascii_glyph = 64'h1838181818187E00;
            "2": ascii_glyph = 64'h3C66060C30607E00;
            "3": ascii_glyph = 64'h3C66061C06663C00;
            "4": ascii_glyph = 64'h0C1C3C6C7E0C0C00;
            "5": ascii_glyph = 64'h7E607C0606663C00;
            "6": ascii_glyph = 64'h1C30607C66663C00;
            "7": ascii_glyph = 64'h7E66060C18181800;
            "8": ascii_glyph = 64'h3C66663C66663C00;
            "9": ascii_glyph = 64'h3C66663E060C3800;
            "A": ascii_glyph = 64'h183C66667E666600;
            "M": ascii_glyph = 64'h63777F6B63636300;
            "B": ascii_glyph = 64'h7C66667C66667C00;
            "C": ascii_glyph = 64'h3C66606060663C00;
            "D": ascii_glyph = 64'h786C6666666C7800;
            "E": ascii_glyph = 64'h7E60607C60607E00;
            "F": ascii_glyph = 64'h7E60607C60606000;
            ":": ascii_glyph = 64'h0018180018180000;
            "+": ascii_glyph = 64'h0018187E18180000;
            "-": ascii_glyph = 64'h0000007E00000000;
            "%": ascii_glyph = 64'h62640C1830264600;
            ".": ascii_glyph = 64'h0000000000001818;
            "*": ascii_glyph = 64'h00663CFF3C660000;
            "X": ascii_glyph = 64'h66663C183C666600;
            ">": ascii_glyph = 64'h6030180C18306000;
            default: ascii_glyph = 64'd0;
        endcase

        case (row)
            4'd0: font_row = char_code[7] ? glyph[255:240] :
                    double_bits(ascii_glyph[63:56]);
            4'd1: font_row = char_code[7] ? glyph[239:224] :
                    double_bits(ascii_glyph[63:56]);
            4'd2: font_row = char_code[7] ? glyph[223:208] :
                    double_bits(ascii_glyph[55:48]);
            4'd3: font_row = char_code[7] ? glyph[207:192] :
                    double_bits(ascii_glyph[55:48]);
            4'd4: font_row = char_code[7] ? glyph[191:176] :
                    double_bits(ascii_glyph[47:40]);
            4'd5: font_row = char_code[7] ? glyph[175:160] :
                    double_bits(ascii_glyph[47:40]);
            4'd6: font_row = char_code[7] ? glyph[159:144] :
                    double_bits(ascii_glyph[39:32]);
            4'd7: font_row = char_code[7] ? glyph[143:128] :
                    double_bits(ascii_glyph[39:32]);
            4'd8: font_row = char_code[7] ? glyph[127:112] :
                    double_bits(ascii_glyph[31:24]);
            4'd9: font_row = char_code[7] ? glyph[111:96] :
                    double_bits(ascii_glyph[31:24]);
            4'd10: font_row = char_code[7] ? glyph[95:80] :
                     double_bits(ascii_glyph[23:16]);
            4'd11: font_row = char_code[7] ? glyph[79:64] :
                     double_bits(ascii_glyph[23:16]);
            4'd12: font_row = char_code[7] ? glyph[63:48] :
                     double_bits(ascii_glyph[15:8]);
            4'd13: font_row = char_code[7] ? glyph[47:32] :
                     double_bits(ascii_glyph[15:8]);
            4'd14: font_row = char_code[7] ? glyph[31:16] :
                     double_bits(ascii_glyph[7:0]);
            default: font_row = char_code[7] ? glyph[15:0] :
                         double_bits(ascii_glyph[7:0]);
        endcase
    end
endfunction
integer i;
reg [15:0] held_a,held_b;
initial begin
repeat(4) @(negedge clk);
for(i=0;i<4096;i=i+1) begin
    ca=i/16; ra=i%16; cb=255-ca; rb=15-ra;
    @(posedge clk); #1;
    if(da!==font_row(ca,ra) || db!==font_row(cb,rb)) $fatal(1,"TEST_FAIL font %h %d got %h want %h B %h %h",ca,ra,da,font_row(ca,ra),db,font_row(cb,rb));
    @(negedge clk);
end
held_a=da; held_b=db; ena=0; enb=0;
ca=8'h80; cb=8'h41; ra=3; rb=4;
repeat(3) @(negedge clk);
if(da!==held_a || db!==held_b) $fatal(1,"TEST_FAIL disabled ports must hold");
ena=1; @(posedge clk); #1;
if(da!==font_row(ca,ra) || db!==held_b) $fatal(1,"TEST_FAIL independent CE A");
@(negedge clk); enb=1; @(posedge clk); #1;
if(db!==font_row(cb,rb)) $fatal(1,"TEST_FAIL independent CE B");
$display("TEST_PASS 8192 dual-port OSD font rows and independent CE against retained golden function"); $finish;
end
endmodule
