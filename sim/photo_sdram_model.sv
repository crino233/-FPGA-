`timescale 1ns/1ps
module photo_sdram_model #(
    parameter integer memory_words=2097152
) (
    input wire clk, input wire rst, input wire ready,
    input wire ras_n, input wire cas_n, input wire we_n,
    input wire [1:0] bank, input wire [10:0] address,
    input wire [3:0] mask, inout wire [31:0] dq
);
    reg [31:0] memory [0:memory_words-1];
    integer open_row [0:3];
    integer write_left=0, write_pos=0, read_pos=0, cycle_count=0;
    reg [31:0] response_data [0:63];
    reg [63:0] response_valid=0;
    reg [31:0] dq_data;
    reg dq_en=0;
    assign dq=dq_en ? dq_data : 32'bz;
    always @(posedge clk) begin
        cycle_count=cycle_count+1;
        if(rst) begin write_left=0; response_valid=0; end
        else if(ready) begin
            if({ras_n,cas_n,we_n}==3'b011) open_row[bank]=address;
            if({ras_n,cas_n,we_n}==3'b100) begin
                write_pos=(open_row[bank]*4+bank)*256+address[7:0]; write_left=4;
            end
            if(write_left!=0) begin
                if(write_pos>=memory_words) $fatal(1,"SDRAM write outside model capacity");
                for(integer lane=0;lane<4;lane=lane+1)
                    if(!mask[lane]) memory[write_pos][lane*8+:8]=dq[lane*8+:8];
                write_pos=write_pos+1; write_left=write_left-1;
            end
            if({ras_n,cas_n,we_n}==3'b101) begin
                read_pos=(open_row[bank]*4+bank)*256+address[7:0];
                if(read_pos+3>=memory_words) $fatal(1,"SDRAM read outside model capacity");
                for(integer beat=0;beat<4;beat=beat+1) begin
                    response_data[(cycle_count+2+beat)%64]=memory[read_pos+beat];
                    response_valid[(cycle_count+2+beat)%64]=1;
                end
            end
        end
    end
    always @(negedge clk) begin
        dq_en=response_valid[cycle_count%64];
        dq_data=response_data[cycle_count%64];
        response_valid[cycle_count%64]=0;
    end
endmodule
