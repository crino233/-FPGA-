`timescale 1ns/1ps
module tb_photo_transition;
    reg mem_clk=0,pix_clk=0,mem_rst_n=0,pix_rst_n=0;
    always #4 mem_clk=~mem_clk;
    always #20 pix_clk=~pix_clk;
    reg allow_transition=1,display_ready=1,target_ready=0;
    reg [1:0] transition_mode=0;
    reg [3:0] requested_index=0,display_index=0,visible_index=0,incoming_index=0;
    reg visible_valid=1,incoming_valid=1,frame_start=0;
    wire display_publish_enable,transition_busy;
    wire [7:0] background_alpha;
    wire wipe_active;
    wire [4:0] wipe_ramp;
    integer result_file;
    photo_transition_control dut(
        .mem_clk(mem_clk),.mem_rst_n(mem_rst_n),.allow_transition(allow_transition),
        .transition_mode(transition_mode),.display_ready(display_ready),
        .requested_index(requested_index),.display_index(display_index),.target_ready(target_ready),
        .display_publish_enable(display_publish_enable),.transition_busy(transition_busy),
        .pix_clk(pix_clk),.pix_rst_n(pix_rst_n),.frame_start(frame_start),
        .incoming_valid(incoming_valid),.incoming_index(incoming_index),
        .visible_valid(visible_valid),.visible_index(visible_index),
        .background_alpha(background_alpha),.wipe_active(wipe_active),.wipe_ramp(wipe_ramp)
    );
    task automatic frame_proc;
        begin
            repeat(4)@(negedge pix_clk);
            frame_start=1;@(negedge pix_clk);frame_start=0;
            repeat(5)@(negedge mem_clk);
        end
    endtask
    task automatic pixel_settle;
        repeat(8)@(negedge pix_clk);
    endtask
    task automatic fade_start(input integer index);
        begin
            @(negedge mem_clk);transition_mode=1;requested_index=index;target_ready=1;
            pixel_settle();
            if(!dut.transaction_active || display_publish_enable || background_alpha!=255)
                $fatal(1,"fade did not arm without changing mid-frame brightness");
        end
    endtask
    task automatic abort_proc(input bit emergency);
        begin
            @(negedge mem_clk);
            if(emergency)allow_transition=0;else requested_index=display_index;
            pixel_settle();frame_proc();pixel_settle();
            if(transition_busy || !display_publish_enable || background_alpha!=255 || wipe_active)
                $fatal(1,"abort did not restore bypass");
            @(negedge mem_clk);requested_index=display_index;allow_transition=1;
            pixel_settle();
        end
    endtask
    initial begin
        result_file=$fopen("tb_photo_transition.result","w");
        repeat(4)@(negedge pix_clk);mem_rst_n=1;pix_rst_n=1;pixel_settle();
        requested_index=1;
        repeat(2)@(negedge mem_clk);
        if(!display_publish_enable || transition_busy)$fatal(1,"OFF changed fast publication");
        transition_mode=1;
        repeat(5)frame_proc();
        if(display_publish_enable || background_alpha!=255 || dut.transaction_active)
            $fatal(1,"cold target changed the old picture before readiness");
        fade_start(1);
        for(integer step=15;step>=0;step=step-1)begin
            frame_proc();
            if(background_alpha!=step*16)$fatal(1,"fade-out step %0d got %0d",step,background_alpha);
            if(step!=0 && display_publish_enable)$fatal(1,"fade published before black");
        end
        if(!display_publish_enable)$fatal(1,"black did not release publication");
        display_index=1;incoming_index=1;
        repeat(2)frame_proc();
        if(background_alpha!=0)$fatal(1,"fade-in began without visible target pixels");
        visible_index=1;
        for(integer step=1;step<=16;step=step+1)begin
            frame_proc();
            if(background_alpha!=(step==16 ? 255:step*16))$fatal(1,"fade-in step %0d",step);
        end
        pixel_settle();
        if(transition_busy)$fatal(1,"fade did not acknowledge completion");
        repeat(4)frame_proc();
        if(transition_busy || background_alpha!=255)$fatal(1,"same picture restarted the effect");
        $fdisplay(result_file,"PASS OFF fast publication; cold load holds old frame; fade publishes at black, waits for target visibility, runs once");

        @(negedge mem_clk);transition_mode=2;requested_index=2;target_ready=1;
        pixel_settle();
        if(!display_publish_enable || wipe_active)$fatal(1,"wipe preparation/ack");
        display_index=2;
        @(negedge pix_clk);incoming_index=2;#1;
        if(!wipe_active || wipe_ramp!=0)$fatal(1,"first target pixel could escape the wipe mask");
        pixel_settle();visible_index=2;
        for(integer step=1;step<=16;step=step+1)begin
            frame_proc();
            if(step<16 && (!wipe_active || wipe_ramp!=step))$fatal(1,"wipe step %0d",step);
        end
        pixel_settle();
        if(transition_busy || wipe_active)$fatal(1,"wipe did not complete");
        $fdisplay(result_file,"PASS wipe mask is armed before first target pixel, progresses on frame boundaries, and finishes once");

        fade_start(3);frame_proc();abort_proc(1);
        fade_start(3);repeat(16)frame_proc();abort_proc(1);
        fade_start(3);frame_proc();abort_proc(0);
        fade_start(3);repeat(16)frame_proc();display_index=3;incoming_index=3;visible_index=3;
        repeat(16)frame_proc();pixel_settle();
        if(transition_busy)$fatal(1,"new transition failed after abort/rearm");
        $fdisplay(result_file,"PASS emergency at fade-out/black and ordinary target cancellation drain the CDC request; next transition succeeds");
        $fdisplay(result_file,"PASS tb_photo_transition");$fclose(result_file);$finish;
    end
    initial begin #2000000;$fatal(1,"transition watchdog");end
endmodule
