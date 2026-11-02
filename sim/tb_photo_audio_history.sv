`timescale 1ns/1ps
module tb_photo_audio_history;
    reg clk=0,rst_n=0,write_en=0;
    always #4 clk=~clk;
    reg [12:0] address=0;
    reg [27:0] data=0;
    reg [4:0] probe_state=0;
    integer result_file;
    function [27:0] expected(input integer value);
        expected=(value*32'h1f1f)^28'ha5a5a5a;
    endfunction
    photo_fat32 #(.image_count(1),.index_bits(1),.request_mode(1),.audio_catalog(1),.max_chain_clusters(8192)) dut(
        .clk(clk),.rst_n(rst_n),.start(1'b0),.busy(),.done(),.error_code(),.resource_valid(),.image_index(),
        .catalog_ready(),.file_req(1'b0),.file_req_index(1'b0),.file_cancel(1'b0),.file_pause(1'b0),.file_cancelled(),
        .aux_req(1'b0),.aux_index(2'd0),.aux_active(),.aux_available(),.aux_error(),.sector_req(),.sector_lba(),
        .sector_busy(1'b0),.sector_valid(1'b0),.sector_data(8'd0),.sector_index(9'd0),.sector_done(1'b0),.sector_error(8'd0),
        .file_start(),.file_size(),.file_valid(),.file_data(),.file_offset(),.file_end(),
        .load_done(1'b0),.load_error(8'd0),.decode_error(8'd0));
    initial begin
        result_file=$fopen("tb_photo_audio_history.result","w");
        force dut.visited_write=write_en;
        force dut.visited_write_addr=address;
        force dut.visited_write_data=data;
        force dut.check_index=address;
        force dut.state=probe_state;
        repeat(6)@(negedge clk);rst_n=1;
        for(integer i=0;i<8192;i=i+1)begin
            @(negedge clk);address=i;data=expected(i);write_en=1;
        end
        @(negedge clk);write_en=0;
        for(integer i=0;i<8192;i=i+1)begin
            @(negedge clk);address=i;probe_state=15;
            @(posedge clk);#1;
            if(dut.visited_data!==expected(i))$fatal(1,"native history address=%d got=%h expected=%h",i,dut.visited_data,expected(i));
        end
        @(negedge clk);probe_state=16;
        repeat(10)begin @(posedge clk);#1;if(dut.visited_data!==expected(8191))$fatal(1,"disabled history port changed");end
        $fdisplay(result_file,"PASS all 8192 native 28-bit history addresses, bank boundaries, synchronous read and disabled hold with official BRAM32K model");
        $fdisplay(result_file,"PASS tb_photo_audio_history");$fclose(result_file);$finish;
    end
endmodule
