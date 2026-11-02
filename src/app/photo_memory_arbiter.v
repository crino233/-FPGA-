`timescale 1ns/1ps
module photo_memory_arbiter #(
    parameter integer refresh_interval_cycles = 1875
) (
    input wire clk, input wire rst_n,
    input wire controller_ready, input wire controller_busy, input wire refresh_active,
    input wire write_request, input wire read_request,
    input wire write_done, input wire read_done,
    output reg write_grant, output reg read_grant,
    output reg refresh_request
);
    localparam [1:0] st_idle=0, st_write=1, st_read=2, st_refresh=3;
    localparam integer refresh_bits=$clog2(refresh_interval_cycles);
    reg [1:0] state;
    reg [refresh_bits-1:0] refresh_tick;
    wire refresh_due=refresh_tick==refresh_interval_cycles-1;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)refresh_tick<=0;
        else if(!controller_ready || refresh_active)refresh_tick<=0;
        else if(!refresh_due)refresh_tick<=refresh_tick+1'b1;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin state<=st_idle; write_grant<=0; read_grant<=0; refresh_request<=0; end
        else begin
            write_grant<=0; read_grant<=0;
            case(state)
                st_idle: if(controller_ready && !controller_busy && !refresh_active) begin
                    if(refresh_due) begin refresh_request<=1; state<=st_refresh; end
                    else if(read_request) begin read_grant<=1; state<=st_read; end
                    else if(write_request) begin write_grant<=1; state<=st_write; end
                end
                st_write: if(write_done) state<=st_idle;
                st_read: if(read_done) state<=st_idle;
                st_refresh: begin
                    if(refresh_active)refresh_request<=0;
                    else if(!refresh_request && !controller_busy)state<=st_idle;
                end
                default: state<=st_idle;
            endcase
        end
    end
endmodule
