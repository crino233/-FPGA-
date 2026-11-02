`timescale 1ns/1ps
module tb_photo_exam_timer;
    reg clk=0, rst_n=0, tick_1ms=0, exam_enable=0, pause_active=0;
    reg start_toggle=0, duration_step=0, reset_cmd=0, pause_cmd=0;
    reg [2:0] duration_index=0;
    wire [31:0] remaining_seconds;
    wire [15:0] remaining_minutes;
    wire [5:0] remaining_second;
    wire running, finished;
    integer result_file;
    always #1 clk=~clk;
    photo_exam_timer timer_proc (
        .clk(clk),.rst_n(rst_n),.tick_1ms(tick_1ms),.exam_enable(exam_enable),
        .pause_active(pause_active),.start_toggle(start_toggle),.duration_step(duration_step),
        .reset_cmd(reset_cmd),.pause_cmd(pause_cmd),.duration_index(duration_index),
        .remaining_seconds(remaining_seconds),.remaining_minutes(remaining_minutes),
        .remaining_second(remaining_second),.running(running),.finished(finished)
    );
    task pulse;
        begin @(negedge clk); tick_1ms=1; @(negedge clk); tick_1ms=0; end
    endtask
    task start_pulse;
        begin @(negedge clk); start_toggle=1; @(negedge clk); start_toggle=0; @(negedge clk); end
    endtask
    task duration_pulse;
        begin @(negedge clk); duration_step=1; @(negedge clk); duration_step=0; @(negedge clk); end
    endtask
    task pause_pulse;
        begin @(negedge clk); pause_cmd=1; @(negedge clk); pause_cmd=0; @(negedge clk); end
    endtask
    integer i,j;
    initial begin
        result_file=$fopen("tb_photo_exam_timer.result","w");
        repeat(3) @(negedge clk); rst_n=1; repeat(3) @(negedge clk);
        if (remaining_seconds!=1800 || running) $fatal(1,"default duration");
        exam_enable=1; start_pulse();
        if (!running) $fatal(1,"start failed");
        for(i=0;i<1000;i=i+1) pulse();
        if (remaining_minutes!=29 || remaining_second!=59 || remaining_seconds!=1799)
            $fatal(1,"one second decrement");
        pause_pulse();
        if (running) $fatal(1,"pause failed");
        pause_active=1; repeat(4) @(negedge clk);
        if (remaining_seconds!=1799) $fatal(1,"fire pause reset countdown");
        pause_active=0; exam_enable=1; duration_index=1; duration_pulse();
        if (remaining_seconds!=3600 || running) $fatal(1,"duration step");
        start_pulse(); if (!running) $fatal(1,"restart failed");
        duration_index=0;reset_cmd=1; repeat(2) @(negedge clk); reset_cmd=0;
        if (remaining_seconds!=1800 || running || finished) $fatal(1,"reset failed");
        for(i=0;i<7;i=i+1) begin
            exam_enable=0;duration_index=i;repeat(2)@(negedge clk);exam_enable=1;
            if(remaining_seconds!=(i==6 ? 60 : (i+1)*1800) ||
                remaining_minutes!=(i==6 ? 1 : (i+1)*30) || remaining_second!=0)
                $fatal(1,"preset mapping index=%0d",i);
            duration_index=(i+1)%7;duration_pulse();
            if(remaining_seconds!=(i==5 ? 60 : i==6 ? 1800 : (i+2)*1800))
                $fatal(1,"preset step/wrap index=%0d",i);
        end
        $fdisplay(result_file,"PASS seven presets: original six indices unchanged, demo index 6 and wrap to 30 minutes");
        duration_index=6;reset_cmd=1;repeat(2)@(negedge clk);reset_cmd=0;
        start_pulse();repeat(999)pulse();
        if(remaining_seconds!=60 || remaining_minutes!=1 || remaining_second!=0)
            $fatal(1,"demo decremented before 1000 ticks");
        pulse();
        if(remaining_seconds!=59 || remaining_minutes!=0 || remaining_second!=59)
            $fatal(1,"demo 01:00 to 00:59 borrow");
        start_pulse();repeat(1000)pulse();
        if(running || remaining_seconds!=59)$fatal(1,"demo user pause");
        start_pulse();pause_active=1;repeat(1000)pulse();pause_active=0;
        if(running || remaining_seconds!=59)$fatal(1,"demo fire pause");
        start_pulse();
        for(i=58;i>=0;i=i-1)begin
            for(j=0;j<1000;j=j+1)pulse();
            if(remaining_seconds!=i || remaining_minutes!=0 || remaining_second!=i ||
                finished!=(i==0) || running!=(i!=0))
                $fatal(1,"demo countdown at %0d seconds",i);
        end
        repeat(2000)pulse();start_pulse();duration_pulse();
        if(remaining_seconds!=0 || running || !finished)$fatal(1,"demo finish underflow/restart lock");
        reset_cmd=1;repeat(2)@(negedge clk);reset_cmd=0;
        if(remaining_seconds!=60 || remaining_minutes!=1 || remaining_second!=0 || running || finished)
            $fatal(1,"demo reset did not rearm 01:00");
        start_pulse();if(!running)$fatal(1,"demo restart after reset");
        $fdisplay(result_file,"PASS full 60-second demo countdown, millisecond boundary, user/fire pause, zero clamp, finish lock and reset/restart");
        $fdisplay(result_file,"PASS tb_photo_exam_timer");
        $fclose(result_file);
        $display("PASS exam timer seven presets and complete one-minute demonstration");
        $finish;
    end
endmodule
