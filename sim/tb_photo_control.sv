`timescale 1ns/1ps
module tb_photo_control;
    integer result_file;
    initial result_file=$fopen("tb_photo_control.result","w");
    reg clk=0, rst_n=0;
    always #4 clk=~clk;
    reg key_enable=0, key1_n=0, key2_n=0;
    wire key_tick, key_next, key_auto, key_prev;
    integer next_count=0, auto_count=0, prev_count=0;
    photo_key_input #(.clk_freq_hz(8000),.debounce_ms(3),.long_press_ms(12)) key_proc (
        .clk(clk),.rst_n(rst_n),.enable(key_enable),.key1_n(key1_n),.key2_n(key2_n),
        .timer_en(1'b0),.tick_1ms(key_tick),.next_down(key_next),
        .auto_down(key_auto),.prev_down(key_prev)
    );
    always @(posedge clk) begin
        if (rst_n) begin
            if (key_next) next_count=next_count+1;
            if (key_auto) auto_count=auto_count+1;
            if (key_prev) prev_count=prev_count+1;
        end
    end
    reg ctrl_enable=0, tick_1ms=0, next_down=0, auto_down=0, prev_down=0;
    reg frame_commit=0;
    reg [1:0] active_index=0;
    reg [3:0] valid_mask=4'hf;
    wire [1:0] image_index;
    wire auto_mode, request_busy, timer_en;
    wire [7:0] player_error;
    photo_player_control #(.auto_period_ms(10)) player_proc (
        .clk(clk),.rst_n(rst_n),.enable(ctrl_enable),.tick_1ms(tick_1ms),
        .next_down(next_down),.auto_down(auto_down),.prev_down(prev_down),
        .frame_commit(frame_commit),.active_index(active_index),
        .valid_mask(valid_mask),
        .image_index(image_index),.auto_mode(auto_mode),
        .request_busy(request_busy),.timer_en(timer_en),.error_code(player_error)
    );
    task automatic wait_cycles(input integer count);
        repeat(count) @(negedge clk);
    endtask
    task automatic event_proc(input integer kind);
        begin
            @(negedge clk);
            next_down=kind==0; auto_down=kind==1; prev_down=kind==2;
            @(negedge clk); next_down=0; auto_down=0; prev_down=0;
        end
    endtask
    task automatic tick_proc(input integer count);
        repeat(count) begin
            @(negedge clk); tick_1ms=1;
            @(negedge clk); tick_1ms=0;
        end
    endtask
    task automatic commit_proc;
        begin
            @(negedge clk); active_index=image_index; frame_commit=1;
            @(negedge clk); frame_commit=0;
            @(negedge clk);
        end
    endtask
    initial begin
        wait_cycles(8); rst_n=1; key_enable=1;
        wait_cycles(240);
        if(next_count || auto_count || prev_count) $fatal(1,"boot-held keys generated events");
        key1_n=1; key2_n=1; wait_cycles(40);
        key1_n=0; wait_cycles(8); key1_n=1; wait_cycles(40);
        if(next_count) $fatal(1,"key bounce accepted");
        key1_n=0; wait_cycles(240);
        if(next_count!=1 || auto_count || prev_count) $fatal(1,"KEY1 hold repeated");
        key1_n=1; wait_cycles(40); key1_n=0; wait_cycles(40);
        key1_n=1; wait_cycles(40);
        if(next_count!=2) $fatal(1,"KEY1 second press lost");
        key2_n=0; wait_cycles(40);
        if(auto_count || prev_count) $fatal(1,"KEY2 short acted before release");
        key2_n=1; wait_cycles(40);
        if(auto_count!=1 || prev_count) $fatal(1,"KEY2 short classification");
        key2_n=0; wait_cycles(240);
        if(prev_count!=1 || auto_count!=1) $fatal(1,"KEY2 long repeated or toggled auto");
        key2_n=1; wait_cycles(40);
        if(prev_count!=1 || auto_count!=1) $fatal(1,"long release emitted short event");
        wait_cycles(24);
        if(key_proc.ms_tick!=0 || key_tick) $fatal(1,"idle timebase did not stop");
        key_enable=0; key1_n=0; wait_cycles(40); key_enable=1; wait_cycles(80);
        if(next_count!=2) $fatal(1,"loading-time press replayed");
        key1_n=1; wait_cycles(40); key1_n=0; wait_cycles(40);
        if(next_count!=3) $fatal(1,"release did not rearm KEY1");
        key_enable=0;
        $fdisplay(result_file,"PASS bounce rejection, boot/load release guard, KEY1 one-shot, idle timebase stop");
        $fdisplay(result_file,"PASS KEY2 short on release, long once, no short after long");

        ctrl_enable=1; wait_cycles(2);
        event_proc(0);
        if(!request_busy || image_index!=1 || active_index!=0) $fatal(1,"manual request not held");
        event_proc(0); event_proc(0); event_proc(2);
        commit_proc();
        if(!request_busy || image_index!=0) $fatal(1,"latest queued direction lost");
        commit_proc();
        if(request_busy || active_index!=0) $fatal(1,"queue did not drain once");
        event_proc(2);
        if(image_index!=3) $fatal(1,"previous wrap failed");
        commit_proc(); event_proc(0);
        if(image_index!=0) $fatal(1,"next wrap failed");
        commit_proc();
        $fdisplay(result_file,"PASS committed-index navigation, wrap both ways, one latest manual request while busy");

        event_proc(1); tick_proc(9);
        if(!auto_mode || request_busy) $fatal(1,"auto started too early");
        @(negedge clk); tick_1ms=1; next_down=1;
        @(negedge clk); tick_1ms=0; next_down=0;
        if(!request_busy || image_index!=1) $fatal(1,"manual/auto collision");
        tick_proc(20);
        if(image_index!=1) $fatal(1,"auto repeated while busy");
        @(negedge clk); frame_commit=1;
        @(negedge clk); frame_commit=0;
        if(!request_busy) $fatal(1,"wrong-bank commit acknowledged request");
        commit_proc(); tick_proc(9);
        if(request_busy) $fatal(1,"auto did not restart dwell after commit");
        @(negedge clk); tick_1ms=1; auto_down=1;
        @(negedge clk); tick_1ms=0; auto_down=0;
        if(auto_mode || request_busy || image_index!=1) $fatal(1,"auto disable at deadline flipped image");
        event_proc(1); tick_proc(10);
        if(!auto_mode || !request_busy || image_index!=2) $fatal(1,"auto deadline missing");
        commit_proc(); tick_proc(9);
        @(negedge clk); tick_1ms=1; prev_down=1;
        @(negedge clk); tick_1ms=0; prev_down=0;
        if(!request_busy || image_index!=1) $fatal(1,"previous did not override auto");
        commit_proc();
        event_proc(0); ctrl_enable=0; wait_cycles(2);
        if(request_busy || auto_mode || image_index!=0) $fatal(1,"disable retained playback request");
        ctrl_enable=1; wait_cycles(2);
        if(request_busy || player_proc.manual_pending) $fatal(1,"disabled request replayed");
        active_index=0; valid_mask=4'b1101; wait_cycles(2);
        event_proc(0);
        if(request_busy || image_index!=0 || player_error!=8'he5)
            $fatal(1,"manual bad target did not hold frame with E5 index=%0d busy=%b error=%h",
                   image_index,request_busy,player_error);
        event_proc(0);
        if(!request_busy || image_index!=2 || player_error!=0)
            $fatal(1,"second manual press did not skip bad target index=%0d busy=%b error=%h",
                   image_index,request_busy,player_error);
        commit_proc(); valid_mask=4'b0101;
        event_proc(1); tick_proc(10);
        if(!request_busy || image_index!=0 || player_error!=0)
            $fatal(1,"automatic selection did not skip invalid entries index=%0d busy=%b error=%h",
                   image_index,request_busy,player_error);
        commit_proc();
        $fdisplay(result_file,"PASS manual E5 hold/second-press skip and automatic valid-mask selection");
        event_proc(0); @(negedge clk); rst_n=0; wait_cycles(2);
        if(request_busy || auto_mode || image_index!=0) $fatal(1,"reset did not clear playback");
        $fdisplay(result_file,"PASS manual/auto arbitration, disable at deadline, matching commit, dwell restart, reset");
        $fdisplay(result_file,"PASS tb_photo_control");
        $fclose(result_file); $finish;
    end
    initial begin #1000000; $fatal(1,"control watchdog"); end
endmodule
