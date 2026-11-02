module photo_sdram (
    input wire clk, input wire clk_sft, input wire reset_req,
    input wire refresh_request,
    output wire controller_ready, output wire refresh_active, output wire controller_busy,
    input wire app_wr_en, input wire [20:0] app_wr_addr,
    input wire [3:0] app_wr_mask, input wire [31:0] app_wr_data,
    input wire app_rd_en, input wire [20:0] app_rd_addr,
    output wire sdram_rd_valid, output wire [31:0] sdram_rd_data
);
    wire sdram_clk, ras_n, cas_n, we_n;
    wire [1:0] bank;
    wire [10:0] address;
    wire [3:0] mask;
    wire [31:0] dq;
    sdr_as_ram #(.self_refresh_open(1'b1)) u2_ram (
        .Sdr_clk(clk),.Sdr_clk_sft(clk_sft),.Rst(reset_req),
        .Sdr_init_done(controller_ready),.Sdr_init_ref_vld(refresh_active),.Sdr_busy(controller_busy),
        .App_ref_req(refresh_request),.App_wr_en(app_wr_en),.App_wr_addr(app_wr_addr),
        .App_wr_dm(app_wr_mask),.App_wr_din(app_wr_data),.App_rd_en(app_rd_en),
        .App_rd_addr(app_rd_addr),.Sdr_rd_en(sdram_rd_valid),.Sdr_rd_dout(sdram_rd_data),
        .SDRAM_CLK(sdram_clk),.SDR_RAS(ras_n),.SDR_CAS(cas_n),.SDR_WE(we_n),
        .SDR_BA(bank),.SDR_ADDR(address),.SDR_DM(mask),.SDR_DQ(dq));
    EG_PHY_SDRAM_2M_32 sdram (
        .clk(sdram_clk),.ras_n(ras_n),.cas_n(cas_n),.we_n(we_n),
        .addr(address),.ba(bank),.dq(dq),.cs_n(1'b0),
        .dm0(mask[0]),.dm1(mask[1]),.dm2(mask[2]),.dm3(mask[3]),.cke(1'b1));
endmodule
