module photo_font_rom (
    input wire clk, input wire enable, input wire [10:0] address,
    output wire [15:0] row_data,
    input wire map_enable, input wire [10:0] map_address,
    output wire [15:0] map_data
);
    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(16),.DATA_WIDTH_B(16),.ADDR_WIDTH_A(11),.ADDR_WIDTH_B(11),
        .DATA_DEPTH_A(2048),.DATA_DEPTH_B(2048),.BYTE_ENABLE(0),.BYTE_A(1),.BYTE_B(1),
        .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),
        .DEBUGGABLE("NO"),.PACKABLE("NO"),.FORCE_KEEP("ON"),
        .INIT_FILE("photo_font.dath"),.FILL_ALL("NONE"),.IMPLEMENT("9K")
    ) glyph_proc (
        .clka(clk),.cea(enable),.ocea(1'b1),.wea(1'b0),.rsta(1'b0),.bea(1'b1),
        .addra(address),.dia(16'd0),.doa(row_data),
        .clkb(clk),.ceb(map_enable),.oceb(1'b1),.web(1'b0),.rstb(1'b0),.beb(1'b1),
        .addrb(map_address),.dib(16'd0),.dob(map_data)
    );
endmodule
