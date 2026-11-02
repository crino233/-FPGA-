`timescale 1ns/1ps
module tb_photo_sdram;
    reg clk=0, rst=1;
    always #4 clk=~clk;
    wire ready, busy, refreshing, read_valid, sdram_clk;
    wire refresh_request;
    photo_memory_arbiter refresh_proc (
        .clk(clk),.rst_n(!rst),.controller_ready(ready),.controller_busy(busy),.refresh_active(refreshing),
        .write_request(1'b0),.read_request(1'b0),.write_done(1'b0),.read_done(1'b0),
        .write_grant(),.read_grant(),.refresh_request(refresh_request));
    reg write_en=0, read_en=0;
    reg [20:0] write_addr=0, read_addr=0;
    reg [31:0] write_data=0;
    wire [31:0] read_data;
    wire ras_n, cas_n, we_n;
    wire [1:0] bank;
    wire [10:0] address;
    wire [3:0] mask;
    tri [31:0] dq;
    integer result_file, writes=0, reads=0, returns=0;
    integer refresh_count=0,refresh_gap=0,max_refresh_gap=0;
    integer open_row [0:3];
    reg [31:0] memory [0:4095];
    integer write_left=0, write_pos=0, read_pos=0, sdram_cycle=0;
    reg [31:0] response_data [0:63];
    reg [63:0] response_valid=0;
    reg [31:0] dq_data;
    reg dq_en=0;
    assign dq=dq_en ? dq_data : 32'bz;

    sdr_as_ram #(.self_refresh_open(1'b1)) dut (
        .Sdr_clk(clk),.Sdr_clk_sft(~clk),.Rst(rst),
        .Sdr_init_done(ready),.Sdr_init_ref_vld(refreshing),.Sdr_busy(busy),
        .App_ref_req(refresh_request),.App_wr_en(write_en),.App_wr_addr(write_addr),
        .App_wr_dm(4'd0),.App_wr_din(write_data),
        .App_rd_en(read_en),.App_rd_addr(read_addr),
        .Sdr_rd_en(read_valid),.Sdr_rd_dout(read_data),
        .SDRAM_CLK(sdram_clk),.SDR_RAS(ras_n),.SDR_CAS(cas_n),.SDR_WE(we_n),
        .SDR_BA(bank),.SDR_ADDR(address),.SDR_DM(mask),.SDR_DQ(dq)
    );

    always @(posedge sdram_clk) begin
        sdram_cycle=sdram_cycle+1;
        if (!rst && ready) begin
            refresh_gap=refresh_gap+1;
            if ({ras_n,cas_n,we_n}==3'b001)begin
                refresh_count=refresh_count+1;
                if(refresh_gap>max_refresh_gap)max_refresh_gap=refresh_gap;
                refresh_gap=0;
            end
            if(refresh_gap>2500)$fatal(1,"SDRAM refresh gap exceeds 20us");
            if ({ras_n,cas_n,we_n}==3'b011) open_row[bank]=address;
            if ({ras_n,cas_n,we_n}==3'b100) begin
                write_pos=(open_row[bank]*4+bank)*256+address[7:0];
                write_left=4;
            end
            if (write_left!=0) begin
                memory[write_pos]=dq;
                writes=writes+1; write_pos=write_pos+1; write_left=write_left-1;
            end
            if ({ras_n,cas_n,we_n}==3'b101) begin
                read_pos=(open_row[bank]*4+bank)*256+address[7:0];
                for(integer beat=0;beat<4;beat=beat+1) begin
                    response_data[(sdram_cycle+2+beat)%64]=memory[read_pos+beat];
                    response_valid[(sdram_cycle+2+beat)%64]=1;
                end
                reads=reads+4;
            end
        end
    end
    always @(negedge sdram_clk) begin
        dq_en=response_valid[sdram_cycle%64];
        dq_data=response_data[sdram_cycle%64];
        response_valid[sdram_cycle%64]=0;
    end
    always @(negedge clk) begin
        if (read_valid) begin
            if (read_data!==(32'h5a000000+returns)) begin
                $fdisplay(result_file,"FAIL returned word=%0d expected=%h actual=%h writes=%0d reads=%0d",
                    returns,32'h5a000000+returns,read_data,writes,reads);
                $fclose(result_file); $fatal(1,"official SDRAM readback mismatch");
            end
            returns=returns+1;
        end
    end
    initial begin
        result_file=$fopen("tb_photo_sdram.result","w");
        repeat(8) @(negedge clk); rst=0;
        wait(ready && !busy && !refreshing);
        @(negedge clk);
        for(integer i=0;i<128;i=i+1) begin
            write_en=1; write_addr=i; write_data=32'h5a000000+i;
            @(negedge clk);
        end
        write_en=0;
        repeat(16) @(negedge clk);
        wait(!busy && !refreshing);
        $fdisplay(result_file,"INFO write burst drained: words=%0d time=%0t",writes,$time);
        @(negedge clk);
        for(integer i=0;i<128;i=i+1) begin
            read_en=1; read_addr=i; @(negedge clk);
        end
        read_en=0;
        repeat(64) @(negedge clk);
        if(returns!=128 || writes!=128) $fatal(1,"SDRAM word count writes=%0d returns=%0d",writes,returns);
        $fdisplay(result_file,"PASS official encrypted controller: 128-word write/drain/read contract");
        repeat(20000)@(negedge clk);
        $fdisplay(result_file,"INFO periodic refresh commands=%0d",refresh_count);
        if(refresh_count<3)$fatal(1,"resident SDRAM has no periodic refresh: commands=%0d",refresh_count);
        $fdisplay(result_file,"PASS periodic SDRAM refresh while application is idle");
        repeat(8750000)@(negedge clk);
        if(refresh_count<2048)$fatal(1,"not all SDRAM rows refreshed in 70ms");
        returns=0;
        wait(!busy && !refreshing);@(negedge clk);
        for(integer i=0;i<128;i=i+1)begin
            read_en=1;read_addr=i;@(negedge clk);
        end
        read_en=0;repeat(64)@(negedge clk);
        if(returns!=128)$fatal(1,"post-retention read count");
        $fdisplay(result_file,"PASS 70ms idle beyond the 64ms refresh window, all 128 words unchanged, refresh commands=%0d max gap=%0d cycles",refresh_count,max_refresh_gap);
        $fdisplay(result_file,"PASS tb_photo_sdram");
        $fclose(result_file); $finish;
    end
    initial begin #100000000; $fatal(1,"SDRAM watchdog"); end
endmodule
