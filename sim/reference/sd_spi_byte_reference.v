`timescale 1ns/1ps
module sd_spi_byte_reference (
    input wire clk, input wire rst_n,
    input wire start, input wire [15:0] clk_div,
    input wire [7:0] tx_data, input wire miso,
    output reg busy, output reg done, output reg [7:0] rx_data,
    output reg sclk, output reg mosi
);
    reg [15:0] div_tick;
    reg [2:0] bit_index;
    reg [7:0] tx_buf, rx_buf;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 0; done <= 0; rx_data <= 0;
            sclk <= 0; mosi <= 1; div_tick <= 0;
            bit_index <= 7; tx_buf <= 0; rx_buf <= 0;
        end else begin
            done <= 0;
            if (!busy) begin
                sclk <= 0;
                if (start) begin
                    busy <= 1; div_tick <= 0; bit_index <= 7;
                    tx_buf <= tx_data; mosi <= tx_data[7]; rx_buf <= 0;
                end
            end else if (div_tick == clk_div - 1'b1) begin
                div_tick <= 0;
                sclk <= ~sclk;
                if (!sclk) begin
                    rx_buf <= {rx_buf[6:0], miso};
                end else if (bit_index == 0) begin
                    busy <= 0; done <= 1; rx_data <= rx_buf; mosi <= 1;
                end else begin
                    bit_index <= bit_index - 1'b1;
                    tx_buf <= {tx_buf[6:0], 1'b1};
                    mosi <= tx_buf[6];
                end
            end else div_tick <= div_tick + 1'b1;
        end
    end
endmodule
