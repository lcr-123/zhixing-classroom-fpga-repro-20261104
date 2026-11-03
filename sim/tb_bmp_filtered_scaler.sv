`timescale 1ns/1ps
module tb_bmp_filtered_scaler #(parameter integer PRODUCTION=0,
                              parameter integer FOCUS_LEFT=0);
    localparam W=PRODUCTION ? 640 : 8;
    localparam H=PRODUCTION ? 480 : 6;
    reg clk=0, rst=1, start=0, source_valid=0;
    reg [15:0] sw=8, sh=6;
    reg [2:0] zoom=2;
    reg [23:0] source_rgb=0;
    wire source_start, output_valid, busy, done, overrun;
    wire [23:0] rgb;
    reg [23:0] captured[0:W*H-1];
    integer count=0, z, pattern;
    always #5 clk=~clk;
    always @(posedge clk) if(output_valid) begin
        if(count>=W*H) $fatal(1,"extra filtered pixel");
        captured[count]=rgb;
        count=count+1;
    end
    bmp_nearest_scaler #(.OUTPUT_WIDTH(W),.OUTPUT_HEIGHT(H),
        .MAX_SOURCE_WIDTH(PRODUCTION ? 1280 : 32),
        .ZOOM_FOCUS_LEFT(FOCUS_LEFT)) dut(
        .clk(clk),.rst(rst),.start(start),.source_width(sw),.source_height(sh),
        .zoom_level(zoom),.source_valid(source_valid),.source_rgb(source_rgb),
        .source_start(source_start),.output_valid(output_valid),.output_rgb(rgb),
        .busy(busy),.done(done),.source_overrun(overrun));

    function automatic [23:0] pixel(input integer x,y,p);
        integer r,g,b;
        begin
            case(p)
                0: begin r=(x*73+y*17)%256;g=(x*19+y*83)%256;b=(x^y)*37%256;end
                1: begin r=((x+y)%2)*255;g=r;b=r;end
                2: begin r=255;g=255;b=255;end
                default: begin r=(x%3==0)?255:0;g=(y%3==0)?255:0;b=0;end
            endcase
            pixel={r[7:0],g[7:0],b[7:0]};
        end
    endfunction
    function automatic [23:0] mix(input [23:0] a,b,input integer w);
        integer r,g,bl;
        begin
            r=(a[23:16]*(4-w)+b[23:16]*w+2)/4;
            g=(a[15:8]*(4-w)+b[15:8]*w+2)/4;
            bl=(a[7:0]*(4-w)+b[7:0]*w+2)/4;
            mix={r[7:0],g[7:0],bl[7:0]};
        end
    endfunction
    task automatic run_case(input integer width,height,level,p);
        integer cw,ch,aw,ah,l,t,ox,oy,x,y,sx,sy,nx,py,wx,wy,remy;
        integer improved;
        reg [23:0] expected,a,b;
        begin
            cw=width;ch=height;aw=W;ah=H;l=0;t=0;
            case(level)
                0:begin aw=W/2;ah=H/2;l=W/4;t=H/4;end
                1:begin aw=W*3/4;ah=H*3/4;l=W/8;t=H/8;end
                3:begin cw=width*4/5;ch=height*4/5;end
                4:begin cw=width*2/3;ch=height*2/3;end
            endcase
            if(cw==0)cw=1;
            if(ch==0)ch=1;
            ox=(width-cw)/2;oy=(height-ch)/2;
            if(FOCUS_LEFT && (level==3 || level==4))ox=0;
            @(negedge clk);count=0;sw=width;sh=height;zoom=level;start=1;
            @(negedge clk);start=0;
            wait(source_start);
            @(negedge clk);
            for(y=0;y<height;y=y+1)for(x=0;x<width;x=x+1)begin
                source_rgb=pixel(x,y,p);source_valid=1;
                @(negedge clk);source_valid=0;
                // A new row starts while the filter still reads the two old
                // rows, exposing accidental overwrite with only two banks.
                repeat(PRODUCTION ? ((width<640 ? 47 : 15)+(x%5)) : 95)@(negedge clk);
            end
            wait(!busy);@(posedge clk);#1;
            if(count!=W*H || overrun)$fatal(1,"count/overrun %0d %b",count,overrun);
            improved=0;
            for(y=0;y<H;y=y+1)for(x=0;x<W;x=x+1)begin
                expected=0;
                if(x>=l && x<l+aw && y>=t && y<t+ah)begin
                    sx=ox+(x-l)*cw/aw;
                    sy=oy+((y-t+1)*ch+ah-1)/ah-1;
                    nx=(sx+1<ox+cw)?sx+1:sx;
                    py=(sy>oy)?sy-1:sy;
                    wx=(cw>aw)?2:(((x-l)*cw%aw)*8+aw)/(2*aw);
                    remy=((y-t+1)*ch-1)%ah+1;
                    wy=(ch>ah)?2:(remy*8+ah)/(2*ah);
                    a=mix(pixel(sx,py,p),pixel(nx,py,p),wx);
                    b=mix(pixel(sx,sy,p),pixel(nx,sy,p),wx);
                    expected=mix(a,b,wy);
                    if(expected!=pixel(sx,sy,p))improved=improved+1;
                    if(width==W && height==H && level==2 && expected!=pixel(x,y,p))
                        $fatal(1,"100 percent is not bit exact");
                    if(p==1 && level==0 && width==W && height==H && expected!=24'h808080)
                        $fatal(1,"2x2 checker did not average to neutral gray");
                end
                if(captured[y*W+x]!==expected)$fatal(1,
                    "filtered %0dx%0d z%0d p%0d at %0d,%0d got=%h expected=%h",
                    width,height,level,p,x,y,captured[y*W+x],expected);
            end
            $display("FILTER_REFERENCE width=%0d height=%0d zoom=%0d pattern=%0d changed=%0d",
                width,height,level,p,improved);
        end
    endtask
    initial begin
        repeat(3)@(negedge clk);rst=0;
        if(PRODUCTION)begin
            for(z=0;z<5;z=z+1)run_case(640,480,z,0);
            run_case(640,480,0,1);
            run_case(321,241,4,3);
            run_case(1280,960,0,0); // maximum four-source-pixel/row step
            run_case(1280,960,2,0);
            run_case(800,600,2,0);
            run_case(320,240,2,0);
        end else begin
            for(pattern=0;pattern<4;pattern=pattern+1)
                for(z=0;z<5;z=z+1)run_case(7,5,z,pattern);
            run_case(8,6,0,1);
            run_case(8,6,1,0); // zero leading border regression
            run_case(8,6,2,0);
            run_case(4,3,4,2); // minimum accepted BMP, clamp last column / first row
            // An intentionally excessive producer rate must raise the sticky
            // error instead of silently claiming a valid converted frame.
            @(negedge clk);sw=8;sh=6;zoom=2;count=0;start=1;
            @(negedge clk);start=0;
            wait(source_start);@(negedge clk);
            repeat(48)begin
                source_valid=1;source_rgb=24'hab12ff;@(negedge clk);
            end
            source_valid=0;
            if(!overrun)$fatal(1,"fast producer overrun was not reported");
            // Reset interrupt must discard partial rows and stale filters.
            rst=1;
            repeat(2)@(negedge clk);rst=0;
            run_case(9,7,4,0);
        end
        $display("TEST_PASS tb_bmp_filtered_scaler production=%0d focus_left=%0d",PRODUCTION,FOCUS_LEFT);$finish;
    end
    initial begin
        #(PRODUCTION ? 2000000000 : 5000000);
        $fatal(1,"filtered scaler timeout");
    end
endmodule
