`timescale 1ns/1ps
module sd_reader_equivalence #(
    parameter integer clk_freq_hz=125000000,init_div=200,data_div=4,max_sector_retries=1
) (
    input wire clk,rst_n,init_start,sector_req,sd_miso,
    input wire [31:0] sector_lba,
    input wire init_done,card_ready,high_capacity,sector_busy,sector_valid,sector_done,
    input wire [7:0] error_code,sector_data,
    input wire [8:0] sector_index,
    input wire sd_cs_n,sd_sclk,sd_mosi,input wire [22:0] state
);
    wire ref_init_done,ref_card_ready,ref_high_capacity,ref_sector_busy,ref_sector_valid,ref_sector_done;
    wire [7:0] ref_error,ref_data;wire [8:0] ref_index;
    wire ref_cs,ref_sclk,ref_mosi;
    integer cycles=0;
    sd_card_reader_reference #(.clk_freq_hz(clk_freq_hz),.init_div(init_div),.data_div(data_div),
        .max_sector_retries(max_sector_retries)) reference_proc(
        .clk(clk),.rst_n(rst_n),.init_start(init_start),.sector_req(sector_req),.sector_lba(sector_lba),.sd_miso(sd_miso),
        .init_done(ref_init_done),.card_ready(ref_card_ready),.high_capacity(ref_high_capacity),
        .sector_busy(ref_sector_busy),.sector_valid(ref_sector_valid),.sector_done(ref_sector_done),
        .error_code(ref_error),.sector_data(ref_data),.sector_index(ref_index),
        .sd_cs_n(ref_cs),.sd_sclk(ref_sclk),.sd_mosi(ref_mosi));
    always @(negedge clk)if(rst_n)begin
        cycles=cycles+1;
        if(!$onehot(state))$fatal(1,"SD state lost one-hot %m state=%h",state);
        if({init_done,card_ready,high_capacity,sector_busy,sector_valid,sector_done,error_code,sector_index,sd_cs_n,sd_sclk,sd_mosi} !==
           {ref_init_done,ref_card_ready,ref_high_capacity,ref_sector_busy,ref_sector_valid,ref_sector_done,ref_error,ref_index,ref_cs,ref_sclk,ref_mosi} ||
            (sector_valid && sector_data!==ref_data))
            $fatal(1,"SD baseline equivalence %m time=%0t state=%h ref=%0d errors=%h/%h",$time,state,reference_proc.state,error_code,ref_error);
    end
    final $display("PASS SD baseline equivalence %m cycles=%0d",cycles);
endmodule
module sd_reader_equivalence_bind;
    bind sd_card_reader sd_reader_equivalence #(.clk_freq_hz(clk_freq_hz),.init_div(init_div),
        .data_div(data_div),.max_sector_retries(max_sector_retries)) equivalence_proc(.*);
endmodule
