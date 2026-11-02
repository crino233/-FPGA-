`timescale 1ns/1ps
module tb_bmp_edges;
    integer result_file;
    initial result_file=$fopen("tb_bmp_edges.result","w");
    reg clk=0,rst_n=0,file_start=0,file_valid=0,file_end=0;
    always #4 clk=~clk;
    reg [31:0] file_size=78,file_offset=0;
    reg [7:0] file_data=0;
    wire pixel_valid,top_down,frame_commit;
    wire [23:0] pixel_data;
    wire [7:0] error_code;
    integer scenario=0,pixel_count=0,commit_count=0;
    photo_bmp_decoder #(.image_width(3),.image_height(2)) dut (
        .clk(clk),.rst_n(rst_n),.file_start(file_start),.file_size(file_size),
        .file_valid(file_valid),.file_data(file_data),.file_offset(file_offset),
        .file_end(file_end),.upstream_error(8'd0),.pixel_valid(pixel_valid),
        .pixel_data(pixel_data),.top_down(top_down),.frame_commit(frame_commit),.error_code(error_code)
    );
    function automatic [7:0] fixture_byte(input integer offset);
        integer p,h;
        begin
            fixture_byte=0; h=scenario==1 ? -2 : 2;
            case(offset)
                0: fixture_byte=scenario==2 ? "X" : "B";
                1: fixture_byte="M";
                2: fixture_byte=78;
                10: fixture_byte=scenario==3 ? 8'hf0 : 54;
                11,12,13: fixture_byte=scenario==3 ? 8'hff : 0;
                14: fixture_byte=40; 18: fixture_byte=3;
                22,23,24,25: fixture_byte=h >> ((offset-22)*8);
                26: fixture_byte=1; 28: fixture_byte=24;
                30: fixture_byte=scenario==5 ? 1 : 0;
                default: if(offset>=54) begin
                    p=(offset-54)%12;
                    if(p<9) case(p%3)
                        0: fixture_byte=8'h11;
                        1: fixture_byte=8'h22;
                        2: fixture_byte=8'h33;
                    endcase
                    else fixture_byte=8'hee;
                end
            endcase
        end
    endfunction
    always @(posedge clk) begin
        if(pixel_valid) begin
            if(pixel_data!==24'h332211) $fatal(1,"BGR/padding decode %h",pixel_data);
            pixel_count=pixel_count+1;
        end
        if(frame_commit) commit_count=commit_count+1;
    end
    task automatic run_case(input integer value,input integer length);
        integer i;
        begin
            @(negedge clk); rst_n=0; file_valid=0; file_end=0;
            scenario=value; pixel_count=0; commit_count=0;
            file_size=value==3 ? 32'hffffffff : 78;
            repeat(4) @(negedge clk); rst_n=1; file_start=1;
            @(negedge clk); file_start=0;
            for(i=0;i<length;i=i+1) begin
                file_valid=1; file_data=fixture_byte(i); file_offset=i;
                file_end=i==length-1;
                @(negedge clk);
            end
            file_valid=0; file_end=0;
            repeat(5) @(negedge clk);
        end
    endtask
    initial begin
        run_case(0,78);
        if(error_code!=0 || pixel_count!=6 || commit_count!=1 || top_down)
            $fatal(1,"padded bottom-up %h pixels=%0d commits=%0d",error_code,pixel_count,commit_count);
        run_case(1,78);
        if(error_code!=0 || pixel_count!=6 || commit_count!=1 || !top_down) $fatal(1,"top-down");
        $fdisplay(result_file,"PASS BMP row padding, BGR conversion, both signs, final byte with EOF");
        run_case(2,78);
        if(error_code!=8'h31 || commit_count!=0) $fatal(1,"signature");
        run_case(3,78);
        if(error_code!=8'h36 || commit_count!=0) $fatal(1,"32-bit offset overflow %h",error_code);
        run_case(4,60);
        if(error_code!=8'h37 || commit_count!=0) $fatal(1,"truncation");
        run_case(5,78);
        if(error_code!=8'h33 || commit_count!=0) $fatal(1,"compression");
        $fdisplay(result_file,"PASS BMP signature, arithmetic overflow, truncation, compression rejection");
        $fdisplay(result_file,"PASS tb_bmp_edges"); $fclose(result_file); $finish;
    end
    initial begin #1000000; $fatal(1,"BMP watchdog"); end
endmodule
