`timescale 1ns/1ps
module tb_photo_image_scale #(
    parameter integer full_size=0
);
    localparam integer output_width=full_size ? 640 : 32;
    localparam integer output_height=full_size ? 480 : 24;
    reg clk=0,rst_n=0,file_start=0,file_valid=0,file_end=0,file_cancelled=0;
    always #4 clk=~clk;
    reg [31:0] file_size=0,file_offset=0;
    reg [7:0] file_data=0,upstream_error=0;
    wire file_block,pixel_valid,top_down,frame_commit,stream_end;
    wire [23:0] pixel_data;
    wire [7:0] error_code;
    wire [11:0] source_width_out,source_height_out;
    integer cycle=0,stall_until=0;
    wire pixel_ready=cycle>=stall_until && cycle%17!=0 && cycle%17!=1;
    integer source_width=64,source_height=64,pixel_origin=54,scenario=0,variant=0;
    bit source_top_down=1;
    integer pixels=0,commits=0,ends=0,blocked=0,peak_bytes=0,cases=0;
    integer result_file;
    string test_name;
    reg previous_stall=0;
    reg [23:0] previous_pixel;
    photo_image_scale #(.image_width(output_width),.image_height(output_height)) dut (
        .clk(clk),.rst_n(rst_n),.file_start(file_start),.file_size(file_size),
        .file_valid(file_valid),.file_data(file_data),.file_offset(file_offset),.file_end(file_end),
        .file_cancelled(file_cancelled),.upstream_error(upstream_error),.file_block(file_block),
        .pixel_ready(pixel_ready),.pixel_valid(pixel_valid),.pixel_data(pixel_data),.top_down(top_down),
        .frame_commit(frame_commit),.stream_end(stream_end),.error_code(error_code),
        .source_width_out(source_width_out),.source_height_out(source_height_out));
    function automatic [23:0] source_rgb(input integer x,input integer y);
        source_rgb={8'(x*17+y*3+variant*19),8'(y*13+x/256),8'(x^y^(variant*37))};
    endfunction
    function automatic [23:0] expected_pixel(input integer position);
        integer k,cw,ch,cx,cy,x,y,sx,sy;
        begin
            k=source_width/4<source_height/3 ? source_width/4 : source_height/3;
            cw=k*4;ch=k*3;cx=(source_width-cw)/2;cy=(source_height-ch)/2;
            x=position%output_width;y=position/output_width;
            if(!source_top_down)y=output_height-1-y;
            sx=cx+((2*x+1)*cw)/(2*output_width);
            sy=cy+((2*y+1)*ch)/(2*output_height);
            expected_pixel=source_rgb(sx,sy);
        end
    endfunction
    function automatic [7:0] fixture_byte(input integer offset);
        integer height_bits,stride,row,x,channel;
        reg [31:0] value;
        reg [23:0] rgb;
        begin
            fixture_byte=0;stride=(source_width*3+3)/4*4;
            height_bits=source_top_down ? -source_height : source_height;
            case(offset)
                0:fixture_byte=scenario==1 ? "X" : "B";
                1:fixture_byte="M";
                2,3,4,5:fixture_byte=file_size>>((offset-2)*8);
                10,11,12,13:begin value=scenario==5 ? 32'hfffffff0 : pixel_origin;fixture_byte=value>>((offset-10)*8);end
                14:fixture_byte=pixel_origin>54 ? 56 : 40;
                18,19,20,21:fixture_byte=source_width>>((offset-18)*8);
                22,23,24,25:begin value=scenario==8 ? 32'h80000000 : height_bits;fixture_byte=value>>((offset-22)*8);end
                26:fixture_byte=1;
                28:fixture_byte=scenario==3 ? 16 : 24;
                30:fixture_byte=scenario==4 ? 1 : 0;
                default:if(offset>=pixel_origin)begin
                    row=(offset-pixel_origin)/stride;
                    x=((offset-pixel_origin)%stride)/3;
                    channel=((offset-pixel_origin)%stride)%3;
                    if(!source_top_down)row=source_height-1-row;
                    rgb=source_rgb(x,row);
                    fixture_byte=x<source_width ? rgb>>(channel*8) : 8'he7;
                end
            endcase
        end
    endfunction
    always @(posedge clk)begin
        cycle=cycle+1;
        if(rst_n)begin
            if(file_block)blocked=blocked+1;
            if(dut.byte_count>peak_bytes)peak_bytes=dut.byte_count;
            if(dut.byte_count>1024)$fatal(1,"source byte buffer overflow");
            if(previous_stall && !file_cancelled && !file_start && error_code==0 &&
                (!pixel_valid || pixel_data!==previous_pixel))$fatal(1,"stalled pixel changed");
            previous_stall=pixel_valid && !pixel_ready;
            previous_pixel=pixel_data;
            if(file_start)previous_stall=0;
            if(pixel_valid && pixel_ready)begin
                if(pixels>=output_width*output_height || pixel_data!==expected_pixel(pixels))
                    $fatal(1,"case %0d %0dx%0d top=%b pixel %0d got=%h expected=%h state=%0d",cases,
                        source_width,source_height,source_top_down,pixels,pixel_data,expected_pixel(pixels),dut.state);
                if(top_down!==source_top_down)$fatal(1,"BMP orientation changed");
                pixels=pixels+1;
            end
            if(frame_commit)begin
                commits=commits+1;
                if(source_width_out!==source_width || source_height_out!==source_height)
                    $fatal(1,"parsed BMP source dimensions disagree with signed-height source fixture");
                if(pixels!=output_width*output_height || !dut.end_flag || dut.byte_count!=0)
                    $fatal(1,"partial source or output was committed");
            end
            if(stream_end)ends=ends+1;
        end
    end
    task automatic run_case(input integer w,input integer h,input bit down,input integer fault,
        input integer origin,input integer truncate_bytes,input integer cancel_at);
        integer length,offset,sector_end,watchdog;
        begin
            @(negedge clk);file_valid=0;file_end=0;file_cancelled=0;upstream_error=0;
            source_width=w;source_height=h;source_top_down=down;scenario=fault;pixel_origin=origin;
            variant=cases;cases=cases+1;pixels=0;commits=0;ends=0;
            file_size=origin+((w*3+3)/4*4)*h;length=file_size-truncate_bytes;
            if(fault!=0 && fault!=7)length=512;
            if(fault==6)file_size=32'hffffffff;
            stall_until=cycle+(cases==1 ? 6000 : 0);
            file_start=1;@(negedge clk);file_start=0;
            offset=0;
            begin: send_file
                while(offset<length)begin
                    while(file_block)begin
                        @(negedge clk);
                        if(cancel_at!=0 && pixels>=cancel_at)disable send_file;
                    end
                    if(cancel_at!=0 && pixels>=cancel_at)disable send_file;
                    sector_end=offset+512;if(sector_end>length)sector_end=length;
                    while(offset<sector_end)begin
                        file_valid=1;file_offset=offset+(fault==7 && offset>=600 ? 1 : 0);
                        if(fault==9 && offset==128)upstream_error=8'h20;
                        file_data=fixture_byte(offset);file_end=offset==length-1 && cancel_at==0;
                        offset=offset+1;@(negedge clk);
                    end
                    file_valid=0;file_end=0;repeat(4)@(negedge clk);
                    if(error_code!=0 && offset<length)disable send_file;
                end
            end
            file_valid=0;file_end=1;
            if(cancel_at!=0)file_cancelled=1;
            @(negedge clk);file_end=0;
            watchdog=0;
            while(ends==0 && watchdog<3000000)begin @(negedge clk);watchdog=watchdog+1;end
            if(ends!=1)$fatal(1,"case %0d failed to finish state=%0d queue=%0d parsed=%0d/%0d pixels=%0d code=%h",cases,
                dut.state,dut.byte_count,dut.parsed_bytes,file_size,pixels,error_code);
            repeat(5)@(negedge clk);
            if(cancel_at!=0)begin
                if(commits!=0)$fatal(1,"cancelled image committed");
            end else if(fault!=0 || truncate_bytes!=0)begin
                if(error_code==0 || commits!=0)$fatal(1,"bad BMP accepted case=%0d code=%h",cases,error_code);
            end else if(error_code!=0 || commits!=1 || pixels!=output_width*output_height)
                $fatal(1,"valid BMP rejected case=%0d code=%h pixels=%0d commits=%0d",cases,error_code,pixels,commits);
            $fdisplay(result_file,"PASS case=%0d source=%0dx%0d top_down=%0b fault=%0d truncate=%0d cancel=%0d pixels=%0d error=%h",
                cases,w,h,down,fault,truncate_bytes,cancel_at,pixels,error_code);
        end
    endtask
    task automatic reset_mid_proc;
        begin
            @(negedge clk);source_width=64;source_height=64;source_top_down=1;
            scenario=0;pixel_origin=54;file_size=54+64*64*3;
            pixels=0;commits=0;ends=0;upstream_error=0;file_cancelled=0;file_start=1;
            file_valid=0;file_end=0;
            @(negedge clk);file_start=0;
            for(integer offset=0;offset<file_size && pixels<10;offset=offset+1)begin
                if(offset%512==0)begin
                    file_valid=0;
                    while(file_block)@(negedge clk);
                end
                file_valid=1;file_offset=offset;file_data=fixture_byte(offset);@(negedge clk);
            end
            file_valid=0;wait(pixels>=10);@(negedge clk);rst_n=0;
            if(pixels>=output_width*output_height)$fatal(1,"mid-row reset fixture completed the image first");
            repeat(4)@(negedge clk);
            if(pixel_valid || frame_commit || stream_end)$fatal(1,"reset exposed stale pixels");
            previous_stall=0;rst_n=1;
            $fdisplay(result_file,"PASS reset during a partially generated target row; next file starts clean");
        end
    endtask
    initial begin
        test_name=full_size ? "tb_photo_image_scale_full" : "tb_photo_image_scale";
        result_file=$fopen({test_name,".result"},"w");
        repeat(5)@(negedge clk);rst_n=1;
        if(full_size)begin
            run_case(640,480,1,0,54,0,0);
            run_case(1001,1001,0,0,86,0,0);
            run_case(64,64,1,0,54,0,0);
            run_case(1920,1080,0,0,54,0,0);
            run_case(2048,1024,0,0,54,0,0);
        end else begin
            run_case(64,64,1,0,54,0,0);
            run_case(65,97,0,0,86,0,0);
            run_case(97,65,1,0,54,0,0);
            run_case(640,480,0,0,54,0,0);
            run_case(640,1024,1,0,54,8,0);
            run_case(64,64,0,0,54,0,100);
            run_case(64,64,1,0,54,0,0);
            run_case(64,64,1,1,54,0,0);
            run_case(2049,64,1,2,54,0,0);
            run_case(63,64,1,2,54,0,0);
            run_case(2048,2048,1,2,54,0,0);
            run_case(64,64,1,3,54,0,0);
            run_case(64,64,1,4,54,0,0);
            run_case(64,64,1,5,54,0,0);
            run_case(64,64,1,6,54,0,0);
            run_case(64,64,1,7,54,0,0);
            run_case(64,64,1,8,54,0,0);
            run_case(64,64,1,9,54,0,0);
            reset_mid_proc();
            run_case(64,64,0,0,54,0,0);
        end
        if(blocked==0 || peak_bytes<512)$fatal(1,"source flow control was not exercised");
        $fdisplay(result_file,"PASS independent center-sampled oracle, native synchronous BRAM, backpressure blocked=%0d peak=%0d",blocked,peak_bytes);
        $fdisplay(result_file,"PASS %s",test_name);$fclose(result_file);$finish;
    end
    initial begin #2000000000;$fatal(1,"image scale watchdog");end
endmodule
