module photo_subtitle_ram (
    input wire mem_clk, input wire mem_en, input wire mem_write_en,
    input wire [10:0] mem_addr, input wire [15:0] mem_write_data, output wire [15:0] mem_read_data,
    input wire pix_clk, input wire read_en, input wire [10:0] read_addr,
    output wire [15:0] read_data
);
    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(16),.DATA_WIDTH_B(16),.ADDR_WIDTH_A(11),.ADDR_WIDTH_B(11),
        .DATA_DEPTH_A(2048),.DATA_DEPTH_B(2048),.BYTE_ENABLE(0),.BYTE_A(1),.BYTE_B(1),
        .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),
        .DEBUGGABLE("NO"),.PACKABLE("NO"),.FORCE_KEEP("ON"),
        .INIT_FILE("photo_subtitle_font.dath"),.FILL_ALL("NONE"),.IMPLEMENT("32K")
    ) ram_proc (
        .clka(mem_clk),.cea(mem_en),.ocea(1'b1),.wea(mem_write_en),.rsta(1'b0),.bea(1'b1),
        .addra(mem_addr),.dia(mem_write_data),.doa(mem_read_data),
        .clkb(pix_clk),.ceb(read_en),.oceb(1'b1),.web(1'b0),.rstb(1'b0),.beb(1'b1),
        .addrb(read_addr),.dib(16'd0),.dob(read_data)
    );
endmodule
