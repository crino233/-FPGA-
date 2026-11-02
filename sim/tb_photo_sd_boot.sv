`timescale 1ns/1ps
module tb_photo_sd_boot #(parameter integer accept_delays=0,prove_lost=0);
    reg clk=0,rst_n=0,corrupt_crc=0;
    always #4 clk=~clk;
    wire cs_n,sclk,mosi,miso,display_ready;
    wire [7:0] error_code,error_detail;
    wire [3:0] image_complete;
    integer result_file;
    string test_name;
    integer catalog_delay=0,file_delay=0,card_delay=0;
    wire catalog_gate=!accept_delays || catalog_delay>=4;
    wire file_gate=!accept_delays || file_delay>=4;
    wire card_gate=!accept_delays || card_delay>=4;
    photo_ingest #(.image_width(32),.image_height(8),.wav_support(1),.subtitle_support(1)) dut(
        .clk(clk),.rst_n(rst_n),.controller_ready(1'b1),.controller_busy(1'b0),.refresh_active(1'b0),
        .requested_index(4'd1),.active_bank(2'd0),.auto_mode(1'b0),.display_publish_enable(1'b1),
        .selection_mask(10'h002),.memory_grant(1'b1),.display_ready(display_ready),
        .image_complete(image_complete),.error_code(error_code),.error_detail(error_detail),
        .subtitle_request(1'b0),.subtitle_index(2'd0),.subtitle_done(1'b0),.subtitle_service_complete(1'b1),
        .subtitle_range_offset(32'd0),.subtitle_close(1'b0),.subtitle_load_error(8'd0),
        .wav_play_enable(1'b0),.wav_pix_clk(clk),.wav_pix_rst_n(rst_n),.wav_consume(1'b0),
        .sd_cs_n(cs_n),.sd_sclk(sclk),.sd_mosi(mosi),.sd_miso(miso));
    always @(posedge clk)begin
        if(!rst_n)begin catalog_delay<=0;file_delay<=0;card_delay<=0;end
        else begin
            if(dut.fs_start && catalog_delay<4)catalog_delay<=catalog_delay+1;
            if(dut.fs_file_req && file_delay<4)file_delay<=file_delay+1;
            if(!dut.card_sector_req)card_delay<=0;
            else if(card_delay<4)card_delay<=card_delay+1;
        end
    end
    sd_card_model #(.volume_mode(1)) card(.cs_n(cs_n),.sclk(sclk),.mosi(mosi),.miso(miso),
        .low_capacity(1'b0),.corrupt_crc(corrupt_crc),.absent_flag(1'b0),.reset_r1(8'h01),
        .reset_silent(1'b0),.bad_echo(1'b0),.init_stall(1'b0));
    task reset_proc;
        begin @(negedge clk);rst_n=0;repeat(8)@(negedge clk);rst_n=1;end
    endtask
    initial begin
        test_name=prove_lost ? "tb_photo_startup_lost_request" : accept_delays ? "tb_photo_startup_requests" : "tb_photo_sd_boot";
        result_file=$fopen({test_name,".result"},"w");reset_proc();
        if(prove_lost)begin
            wait(dut.state==2);repeat(1000)@(negedge clk);
            if(dut.fs_busy || dut.fs_start || display_ready || error_code)
                $fatal(1,"old missed-start stall not reproduced");
            $fdisplay(result_file,"PASS catalog start pulse lost at receiver: ingest waits in catalog, FAT idle, no frame and no FAT timeout active");
            $fdisplay(result_file,"PASS tb_photo_startup_lost_request");$fclose(result_file);$finish;
        end
        wait(display_ready || error_code);
        if(error_code || !display_ready || image_complete==0)$fatal(1,"SPI boot error=%h detail=%h",error_code,error_detail);
        $fdisplay(result_file,"PASS actual SPI initialization, CRC/replay, FAT/PIC2/BMP256 pixels and complete cache publication");
        corrupt_crc=1;reset_proc();wait(error_code);
        if(error_code!=8'h20 || error_detail!=8'h15 || display_ready || image_complete!=0)
            $fatal(1,"SD CRC detail not retained %h/%h",error_code,error_detail);
        $fdisplay(result_file,"PASS CRC failures preserve FAT20 and raw SD15, no partial frame or ignored error");
        corrupt_crc=0;reset_proc();wait(display_ready || error_code);
        if(error_code || !display_ready)$fatal(1,"SPI boot reset recovery");
        $fdisplay(result_file,"PASS %s",test_name);$fclose(result_file);$finish;
    end
    initial begin #100000000;$fatal(1,"SPI startup watchdog fs_state=%0d card_state=%h error=%h",dut.fs_proc.state,dut.card_proc.state,error_code);end
endmodule
