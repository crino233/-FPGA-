`timescale 1ns/1ps
module tb_sd_reset #(
    parameter integer full_rate=0
);
    localparam integer test_freq=full_rate ? 125000000 : 1000000;
    localparam integer test_init_div=full_rate ? 200 : 4;
    reg clk=0,rst_n=0,init_start=0,sector_req=0;
    always #4 clk=~clk;
    reg [7:0] reset_r1=1;
    reg reset_silent=0,bad_echo=0,init_stall=0;
    wire init_done,card_ready,high_capacity,sector_valid,sector_done;
    wire [7:0] error_code,sector_data;
    wire [8:0] sector_index;
    wire cs_n,sclk,mosi,miso;
    integer result_file,received_count=0,cycle_count=0,init_cycle=0,init_count=0;
    sd_card_reader #(.clk_freq_hz(test_freq),.init_div(test_init_div),.data_div(full_rate ? 4 : 2)) dut (
        .clk(clk),.rst_n(rst_n),.init_start(init_start),.init_done(init_done),
        .card_ready(card_ready),.high_capacity(high_capacity),.error_code(error_code),
        .sector_req(sector_req),.sector_lba(32'd3),.sector_busy(),
        .sector_valid(sector_valid),.sector_data(sector_data),.sector_index(sector_index),
        .sector_done(sector_done),.sd_cs_n(cs_n),.sd_sclk(sclk),.sd_mosi(mosi),.sd_miso(miso)
    );
    sd_card_model #(.retain_read(1),.zero_data(1)) card (
        .cs_n(cs_n),.sclk(sclk),.mosi(mosi),.miso(miso),
        .low_capacity(1'b0),.corrupt_crc(1'b0),.absent_flag(1'b0),.cmd16_seen(),
        .reset_r1(reset_r1),.reset_silent(reset_silent),.bad_echo(bad_echo),.init_stall(init_stall)
    );
    always @(posedge clk) begin
        cycle_count=cycle_count+1;
        if(rst_n && init_start) begin init_cycle=cycle_count;init_count=init_count+1; end
        if(rst_n && init_done && cycle_count-init_cycle>test_freq+16)
            $fatal(1,"initialization exceeded original total timeout");
        if(rst_n && sector_valid) begin
            if(!card_ready || sector_index!=received_count || sector_data!==8'h00)
                $fatal(1,"stale/invalid sector replay index=%0d count=%0d data=%h",sector_index,received_count,sector_data);
            received_count=received_count+1;
        end
    end
    task automatic reset_host;
        begin
            @(negedge clk);rst_n=0;init_start=0;sector_req=0;received_count=0;
            #1;
            if(cs_n!==1 || sclk!==0 || mosi!==1) $fatal(1,"unsafe SPI reset levels");
            repeat(8) @(negedge clk);rst_n=1;
            repeat(4) @(negedge clk);init_start=1;
            @(negedge clk);init_start=0;
        end
    endtask
    task automatic finish_init(input reg [7:0] expected_error=0);
        begin
            wait(init_done);@(negedge clk);
            if(error_code!=expected_error || card_ready!=(expected_error==0))
                $fatal(1,"warm reset init error=%h expected=%h ready=%b",error_code,expected_error,card_ready);
        end
    endtask
    task automatic start_sector;
        begin
            received_count=0;
            @(negedge clk);sector_req=1;
            @(negedge clk);sector_req=0;
        end
    endtask
    task automatic check_sector;
        begin
            start_sector();wait(sector_done);@(negedge clk);
            if(error_code!=0 || received_count!=512) $fatal(1,"sector after warm reset count=%0d error=%h",received_count,error_code);
        end
    endtask
    initial begin
        result_file=$fopen(full_rate ? "tb_sd_reset_full.result" : "tb_sd_reset.result","w");
        reset_host();finish_init();check_sector();
        if(full_rate) begin
            start_sector();wait(dut.state[13]);
            @(negedge clk);card.token_delay_left=test_freq/10/(2*test_init_div);
            reset_host();finish_init();check_sector();
            $fdisplay(result_file,"PASS production 125MHz/312.5kHz reset with 100ms pending read, full sector CRC/replay");
            $fdisplay(result_file,"PASS tb_sd_reset_full");$fclose(result_file);$finish;
        end
        start_sector();
        wait(dut.state[5] && dut.cmd_index==17 && dut.cmd_pos==2 && dut.byte_busy && sclk);
        reset_host();finish_init();check_sector();
        $fdisplay(result_file,"PASS host reset inside a partial CMD17 packet");

        start_sector();wait(dut.state[6] && dut.cmd_index==17);
        reset_host();finish_init();check_sector();
        $fdisplay(result_file,"PASS host reset before CMD17 response, pending read survives host reset");

        for(integer i=0;i<3;i=i+1) begin
            start_sector();
            wait(dut.state[16] && dut.data_index==(i==0 ? 0 : (i==1 ? 127 : 511)) &&
                dut.byte_busy && dut.byte_proc.bit_index==3 && sclk);
            reset_host();finish_init();check_sector();
        end
        start_sector();wait(dut.state[18] && !dut.crc_phase && dut.byte_busy && sclk);
        reset_host();finish_init();check_sector();
        $fdisplay(result_file,"PASS unaligned resets in first/middle/last data bytes and CRC, no partial replay");

        reset_host();wait(dut.state[9] && dut.cmd_index==8 && dut.byte_busy && sclk);
        reset_host();finish_init();check_sector();
        $fdisplay(result_file,"PASS second reset inside CMD8 response");

        start_sector();wait(dut.state[13]);
        @(negedge clk);card.token_delay_left=test_freq/10/(2*test_init_div);
        reset_host();
        repeat(3) begin
            wait(dut.state[22] && dut.power_bytes>=16);
            reset_host();
        end
        finish_init();check_sector();
        $fdisplay(result_file,"PASS 100ms-equivalent pending token and repeated reset during recovery clocks");

        begin
            integer before_count;
            before_count=card.cmd0_count;reset_r1=0;
            reset_host();wait(card.cmd0_count==before_count+1);
            @(negedge clk);reset_r1=1;
            finish_init();
            if(card.cmd0_count!=before_count+2) $fatal(1,"transient CMD0 retry count");
        end
        bad_echo=1;reset_host();wait(dut.cmd_index==8 && dut.state[12]);
        @(negedge clk);bad_echo=0;
        finish_init();check_sector();
        $fdisplay(result_file,"PASS transient CMD0 response and false-idle CMD8 echo recover through fresh initialization");

        begin
            integer before_count;
            before_count=card.cmd0_count;reset_r1=0;
            reset_host();finish_init(8'h02);
            if(card.cmd0_count!=before_count+3) $fatal(1,"persistent CMD0 did not stop after three attempts");
            reset_r1=1;reset_silent=1;before_count=card.cmd0_count;
            reset_host();finish_init(8'h01);
            if(card.cmd0_count!=before_count+3) $fatal(1,"silent CMD0 retry limit");
        end
        reset_silent=0;bad_echo=1;reset_host();finish_init(8'h03);bad_echo=0;
        init_stall=1;reset_host();finish_init(8'h08);init_stall=0;
        reset_host();finish_init();check_sector();
        $fdisplay(result_file,"PASS persistent errors retain 01/02/03, original total timeout 08, later reset recovers");
        $fdisplay(result_file,"PASS tb_sd_reset");$fclose(result_file);$finish;
    end
    initial begin #(full_rate ? 2000000000 : 100000000); $fatal(1,"warm reset watchdog state=%0d",dut.state); end
endmodule
