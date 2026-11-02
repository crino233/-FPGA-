`timescale 1ns/1ps
module tb_photo_power_reset;
    reg clk=0,ext_mem_clk=0,video_clk=0,audio_pll_lock=1;
    reg rst_n=0,sw2=0,run_mem=1,run_pix=1;
    always #10 clk=~clk;
    always #4 if(run_mem)ext_mem_clk=~ext_mem_clk;
    always #20 if(run_pix)video_clk=~video_clk;
    `include "work/photo_power_reset_fixture.vh"
    integer result_file;
    initial begin
        result_file=$fopen("tb_photo_power_reset.result","w");
        #1;
        if(rst_all!==1)$fatal(1,"configuration initial state did not hold reset with PLL already locked");
        repeat(15)@(negedge clk);
        if(rst_all!==1)$fatal(1,"power-up reset released before 16 reference clocks");
        repeat(3)@(negedge clk);repeat(5)@(negedge video_clk);
        if(!mem_rst_n || !pix_rst_n || !system_rst_n)$fatal(1,"domain reset release failed");
        repeat(3)begin rst_n=1;sw2=1;#43;rst_n=0;sw2=0;#61;end
        if(rst_all || !mem_rst_n || !pix_rst_n || !system_rst_n)$fatal(1,"K1/SW2 still affect system reset");
        run_mem=0;run_pix=0;#1;audio_pll_lock=0;#1;
        if(!rst_all || mem_rst_n || pix_rst_n || system_rst_n)
            $fatal(1,"PLL loss failed asynchronous assertion while generated clocks stopped");
        audio_pll_lock=1;repeat(22)@(negedge clk);
        if(mem_rst_n || pix_rst_n || !system_rst_n)$fatal(1,"stopped domains released reset without clocks");
        run_mem=1;run_pix=1;repeat(5)@(negedge video_clk);
        if(!mem_rst_n || !pix_rst_n)$fatal(1,"relocked domains failed synchronous release");
        $fdisplay(result_file,"PASS production top reset logic: configuration init with PLL high, 16 reference clocks, stopped-domain lock loss and per-domain release; K1/SW2 independent");
        $fdisplay(result_file,"PASS tb_photo_power_reset");$fclose(result_file);$finish;
    end
    initial begin #10000;$fatal(1,"power reset watchdog");end
endmodule
