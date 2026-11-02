`timescale 1ns/1ps
module tb_photo_image_scale_demo;
    reg clk=0,rst_n=0,file_start=0,file_valid=0,file_end=0;
    always #4 clk=~clk;
    reg [31:0] file_size=0,file_offset=0;
    reg [7:0] file_data=0;
    wire file_block,pixel_valid,top_down,frame_commit,stream_end;
    wire [23:0] pixel_data;
    wire [7:0] error_code;
    wire [11:0] source_width_out,source_height_out;
    integer expected_width,expected_height;
    reg [7:0] source_bytes[0:6291519];
    reg [7:0] expected_bytes[0:921599];
    integer result_file,output_file,pixels=0,commits=0,ends=0,image_index=2;
    integer source_file,expected_file,read_count;
    photo_image_scale dut(
        .clk(clk),.rst_n(rst_n),.file_start(file_start),.file_size(file_size),
        .file_valid(file_valid),.file_data(file_data),.file_offset(file_offset),.file_end(file_end),
        .file_cancelled(1'b0),.upstream_error(8'd0),.file_block(file_block),.pixel_ready(1'b1),
        .pixel_valid(pixel_valid),.pixel_data(pixel_data),.top_down(top_down),
        .frame_commit(frame_commit),.stream_end(stream_end),.error_code(error_code),
        .source_width_out(source_width_out),.source_height_out(source_height_out));
    reg [23:0] actual_pixels[0:307199];
    always @(posedge clk)if(rst_n)begin
        if(pixel_valid)begin
            integer expected_pos;
            reg [23:0] expected_rgb;
            expected_pos=((479-pixels/640)*640+pixels%640)*3;
            expected_rgb={expected_bytes[expected_pos],expected_bytes[expected_pos+1],expected_bytes[expected_pos+2]};
            if(pixel_data!==expected_rgb || pixels>=307200 || top_down)
                $fatal(1,"actual PIC%0d mismatch pixel=%0d got=%h expected=%h",image_index,pixels,pixel_data,expected_rgb);
            actual_pixels[expected_pos/3]=pixel_data;
            pixels=pixels+1;
        end
        if(frame_commit)commits=commits+1;
        if(stream_end)ends=ends+1;
    end
    initial begin
        result_file=$fopen("tb_photo_image_scale_demo.result","w");
        repeat(4)@(negedge clk);rst_n=1;
        for(image_index=2;image_index<=7;image_index=image_index+1)begin
            source_file=$fopen($sformatf("work/image_scale_demo/PIC%0d.BMP",image_index),"rb");
            expected_file=$fopen($sformatf("work/image_scale_preview/pic%0d_expected.rgb",image_index),"rb");
            if(source_file==0 || expected_file==0)$fatal(1,"missing scale demonstration fixture");
            file_size=$fread(source_bytes,source_file);$fclose(source_file);
            read_count=$fread(expected_bytes,expected_file);$fclose(expected_file);
            if(read_count!=921600 || file_size<54)$fatal(1,"truncated demonstration fixture");
            case(image_index)
                2:begin expected_width=1000;expected_height=1000;end
                3:begin expected_width=960;expected_height=540;end
                4:begin expected_width=600;expected_height=1000;end
                5:begin expected_width=320;expected_height=240;end
                6:begin expected_width=641;expected_height=479;end
                default:begin expected_width=1920;expected_height=1080;end
            endcase
            pixels=0;commits=0;ends=0;
            @(negedge clk);file_start=1;
            @(negedge clk);file_start=0;
            for(integer offset=0;offset<file_size;offset=offset+1)begin
                if(offset%512==0)while(file_block)@(negedge clk);
                file_valid=1;file_offset=offset;file_data=source_bytes[offset];file_end=offset==file_size-1;
                @(negedge clk);
                if(offset%512==511)begin file_valid=0;file_end=0;repeat(4)@(negedge clk);end
            end
            file_valid=0;file_end=0;wait(ends==1);repeat(4)@(negedge clk);
            if(error_code!=0 || commits!=1 || pixels!=307200)$fatal(1,"demo did not complete");
            if(source_width_out!==expected_width || source_height_out!==expected_height)
                $fatal(1,"source dimensions PIC%0d got=%0dx%0d expected=%0dx%0d",image_index,
                    source_width_out,source_height_out,expected_width,expected_height);
            output_file=$fopen($sformatf("work/image_scale_preview/pic%0d_rtl.rgb",image_index),"wb");
            for(integer pos=0;pos<307200;pos=pos+1)
                $fwrite(output_file,"%c%c%c",actual_pixels[pos][23:16],actual_pixels[pos][15:8],actual_pixels[pos][7:0]);
            $fclose(output_file);
            $fdisplay(result_file,"PASS actual PIC%0d BMP (%0d bytes), all 307200 output pixels match independent software oracle",image_index,file_size);
        end
        $fdisplay(result_file,"PASS tb_photo_image_scale_demo");$fclose(result_file);$finish;
    end
    initial begin #2000000000;$fatal(1,"actual BMP scaling watchdog");end
endmodule
