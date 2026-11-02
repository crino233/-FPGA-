`timescale 1ns/1ps
module tb_photo_badge;
    integer result_file;
    reg clk=0, rst_n=0;
    always #4 clk=~clk;
    reg enable=0, physical_mode=0, test_consume=0,key1_n=1,test_key1=0;
    reg [2:0] keys_n=0;
    reg sw1=0, sw3=1, sw4=1;
    wire key_tick, music_mute, exam_request, fire_request;
    wire [2:0] key_short, key_long;
    wire key1_short;
    reg control_tick=0, test_exam=0, test_fire=0, test_mute=0, exam_done=0;
    reg [2:0] test_short=0, test_long=0;
    wire [2:0] short_event=physical_mode ? key_short : test_short;
    wire key1_short_event=physical_mode ? key1_short : test_key1;
    wire [2:0] long_event=physical_mode ? key_long : test_long;
    wire consume_event, auto_mode, temporary_pause, menu_active, page_change, page_return_valid;
    wire [1:0] page_group, menu_adjust, scene_mode;
    wire [2:0] menu_item;
    wire [1:0] eye_mode;
    wire [1:0] transition_mode;
    wire [2:0] subtitle_speed,subtitle_alpha;
    wire [3:0] page_return_index;
    wire next_down, prev_down, auto_step, music_enable, player_busy;
    wire exam_start_toggle, exam_duration_step, exam_reset, exam_pause, exam_finish;
    wire exam_started, exam_running, exam_finished;
    wire [2:0] exam_duration_index, music_volume, brightness_level;
    wire [15:0] slideshow_ms;
    wire [4:0] slideshow_seconds;
    wire resolution_notice;
    wire [31:0] timer_seconds;
    wire timer_running;
    reg [3:0] active_index=0;
    reg [9:0] valid_mask=10'h3ff;
    reg frame_commit=0;
    wire [3:0] requested_index;
    wire [7:0] player_error;
    reg [9:0] selection_mask=10'h3ff;
    reg target_valid=0;
    reg [3:0] target_index=0;
    reg check_no_error=0;
    integer short_count[0:2], long_count[0:2], finish_count=0,key1_count=0,resolution_count=0;
    integer i, before_short, before_long;
    reg pll_lock=1;
    wire system_reset_n;
    photo_reset_sync reset_lock_proc(.clk(clk),.reset_req(!pll_lock),.rst_n(system_reset_n));
    photo_badge_input #(.clk_freq_hz(8000),.debounce_ms(3),.long_press_ms(12)) input_proc (
        .clk(clk),.rst_n(rst_n),.enable(enable),.consume(test_consume || (physical_mode && consume_event)),
        .key1_n(key1_n),
        .key2_n(keys_n[0]),.key3_n(keys_n[1]),.key4_n(keys_n[2]),
        .sw1(sw1),.sw3(sw3),.sw4(sw4),.tick_1ms(key_tick),
        .key1_short_event(key1_short),
        .short_event(key_short),.long_event(key_long),
        .music_mute(music_mute),.exam_request(exam_request),.fire_request(fire_request)
    );
    photo_badge_control #(.pause_timeout_ms(10),.menu_timeout_ms(5),.auto_period_ms(5)) control_proc (
        .clk(clk),.rst_n(rst_n),.enable(enable),.tick_1ms(control_tick),
        .short_event(short_event),.long_event(long_event),.key1_short_event(key1_short_event),
        .exam_request(physical_mode ? exam_request : test_exam),
        .fire_request(physical_mode ? fire_request : test_fire),
        .music_mute(physical_mode ? music_mute : test_mute),
        .player_busy(player_busy),.frame_commit(frame_commit),.active_index(active_index),.exam_done(exam_done),
        .config_apply(1'b0),.config_data(19'd0),
        .player_next_down(next_down),.player_prev_down(prev_down),.player_auto_step(auto_step),
        .auto_mode(auto_mode),.consume_event(consume_event),.temporary_pause(temporary_pause),
        .page_group(page_group),.page_change(page_change),.page_return_index(page_return_index),
        .page_return_valid(page_return_valid),.menu_active(menu_active),.menu_item(menu_item),
        .menu_adjust(menu_adjust),.music_volume(music_volume),.brightness_level(brightness_level),
        .eye_mode(eye_mode),.subtitle_speed(subtitle_speed),.subtitle_alpha(subtitle_alpha),.transition_mode(transition_mode),
        .resolution_notice(resolution_notice),
        .slideshow_ms(slideshow_ms),.slideshow_seconds(slideshow_seconds),.exam_start_toggle(exam_start_toggle),
        .exam_duration_step(exam_duration_step),.exam_reset(exam_reset),
        .exam_pause(exam_pause),.exam_finish(exam_finish),.exam_started(exam_started),
        .exam_running(exam_running),.exam_finished(exam_finished),.exam_duration_index(exam_duration_index),
        .music_enable(music_enable),.scene_mode(scene_mode)
    );
    photo_exam_timer timer_proc (
        .clk(clk),.rst_n(rst_n),.tick_1ms(control_tick),
        .exam_enable(physical_mode ? exam_request : test_exam),
        .pause_active(physical_mode ? fire_request : test_fire),
        .start_toggle(exam_start_toggle),.duration_step(exam_duration_step),
        .reset_cmd(exam_reset),.pause_cmd(exam_pause),.duration_index(exam_duration_index),
        .remaining_seconds(timer_seconds),.remaining_minutes(),.remaining_second(),
        .running(timer_running),.finished()
    );
    photo_player_control #(.image_count(10),.external_control(1)) player_proc (
        .clk(clk),.rst_n(rst_n),.enable(enable),.tick_1ms(1'b0),
        .next_down(next_down),.prev_down(prev_down),.auto_down(1'b0),
        .external_auto(auto_mode),.auto_step(auto_step),.discard_events(consume_event),
        .selection_mask(selection_mask),.target_valid(target_valid),.target_index(target_index),
        .frame_commit(frame_commit),.active_index(active_index),.valid_mask(valid_mask),
        .image_index(requested_index),.auto_mode(),.request_busy(player_busy),.timer_en(),.error_code(player_error)
    );
    reg image_change=0;
    wire sample_valid, cue_active;
    wire signed [15:0] sample_data;
    integer audible_cue=0, sample_seen=0;
    photo_audio_tone #(.note_samples(8),.cue_samples(4)) tone_proc (
        .clk(clk),.rst_n(rst_n),.enable(1'b1),.music_enable(music_enable),
        .image_change(image_change),.image_index(2'd0),
        .audio_scene(2'd0),.music_volume(3'd4),
        .sample_valid(sample_valid),.sample_data(sample_data),.cue_active(cue_active)
    );
    always @(posedge clk) begin
        for(integer j=0;j<3;j=j+1) begin
            if(key_short[j]) short_count[j]=short_count[j]+1;
            if(key_long[j]) long_count[j]=long_count[j]+1;
        end
        if(key1_short)key1_count=key1_count+1;
        if(resolution_notice)resolution_count=resolution_count+1;
        if(exam_finish) finish_count=finish_count+1;
        if(check_no_error && player_error!=0) begin
            $display("BADERR t=%0t err=%h req=%0d active=%0d sel=%h valid=%h busy=%b search=%b si=%0d sc=%0d manual=%b bad=%b", $time, player_error, requested_index, active_index, selection_mask, valid_mask, player_busy, player_proc.search_flag, player_proc.search_index, player_proc.search_count, player_proc.request_manual, player_proc.manual_bad_pending);
            $fatal(1,"unexpected player error during valid group navigation");
        end
    end
    always @(negedge clk) begin
        if(sample_valid) begin
            sample_seen=sample_seen+1;
            if(cue_active && sample_data!=0) audible_cue=audible_cue+1;
        end
    end
    task automatic cycles(input integer count);
        repeat(count) @(negedge clk);
    endtask
    task automatic input_ms(input integer count);
        cycles(count*8);
    endtask
    task automatic event_proc(input [2:0] short_value,input [2:0] long_value);
        begin
            @(negedge clk); test_short=short_value; test_long=long_value;
            @(negedge clk); test_short=0; test_long=0;
            cycles(4);
        end
    endtask
    task automatic key1_event_proc;
        begin
            @(negedge clk);test_key1=1;
            @(negedge clk);test_key1=0;
            cycles(4);
        end
    endtask
    task automatic tick_proc(input integer count);
        begin
            repeat(count) begin
                @(negedge clk); control_tick=1;
                @(negedge clk); control_tick=0;
            end
            cycles(4);
        end
    endtask
    task automatic commit_proc;
        begin
            @(negedge clk); active_index=requested_index; frame_commit=1;
            @(negedge clk); frame_commit=0;
            cycles(4);
        end
    endtask
    task automatic reset_proc;
        begin
            @(negedge clk); rst_n=0; enable=0; physical_mode=0;key1_n=1;test_key1=0;
            test_short=0; test_long=0; control_tick=0; active_index=0; frame_commit=0;
            test_exam=0; test_fire=0; test_mute=0; exam_done=0;
            valid_mask=10'h3ff;
            selection_mask=10'h3ff; target_valid=0; target_index=0;
            cycles(4); rst_n=1; cycles(4); enable=1; cycles(6);
        end
    endtask
    task automatic select_group(input [9:0] mask,input [3:0] index);
        begin
            @(negedge clk); selection_mask=mask; target_index=index; target_valid=1;
            @(negedge clk); target_valid=0;
            cycles(4);
        end
    endtask
    initial begin
        result_file=$fopen("tb_photo_badge.result","w");
        for(i=0;i<3;i=i+1) begin short_count[i]=0; long_count[i]=0; end
        pll_lock=1;#1;pll_lock=0;#1;
        if(system_reset_n!==0)$fatal(1,"PLL unlock did not assert system reset");
        pll_lock=1;cycles(5);
        if(system_reset_n!==1)$fatal(1,"PLL lock did not synchronously release reset");
        key1_n=0;input_ms(4);key1_n=1;input_ms(4);
        if(system_reset_n!==1)$fatal(1,"K1 input changed system reset");
        pll_lock=0;#1;
        if(system_reset_n!==0)$fatal(1,"PLL loss did not reassert system reset");
        pll_lock=1;cycles(5);
        if(system_reset_n!==1)$fatal(1,"system did not recover after PLL relock");
        $fdisplay(result_file,"PASS configuration-start reset source and PLL lock-loss recovery are independent of K1");
        reset_proc();
        input_ms(30);
        for(i=0;i<3;i=i+1)
            if(short_count[i] || long_count[i]) $fatal(1,"boot-held key emitted event %0d",i);
        if(exam_request || fire_request) $fatal(1,"boot-high switches bypassed guard");
        before_short=key1_count;key1_n=0;input_ms(1);key1_n=1;input_ms(6);
        if(key1_count!=before_short)$fatal(1,"K1 debounce accepted bounce");
        key1_n=0;input_ms(6);
        if(key1_count!=before_short)$fatal(1,"K1 short event fired before release");
        key1_n=1;input_ms(6);
        if(key1_count!=before_short+1)$fatal(1,"K1 short event missing");
        key1_n=0;input_ms(30);key1_n=1;input_ms(6);
        if(key1_count!=before_short+1)$fatal(1,"K1 long press generated an action");
        before_short=key1_count;enable=0;key1_n=0;input_ms(6);enable=1;input_ms(20);
        key1_n=1;input_ms(6);
        if(key1_count!=before_short)$fatal(1,"K1 disabled/boot-held press replayed on release");
        key1_n=0;input_ms(6);test_consume=1;cycles(1);test_consume=0;
        input_ms(6);key1_n=1;input_ms(6);
        if(key1_count!=before_short)$fatal(1,"K1 consumed press replayed across a page boundary");
        $fdisplay(result_file,"PASS K1 active-low debounce, release-only short event and long-press suppression");
        keys_n=7; input_ms(6);
        for(i=0;i<3;i=i+1) begin
            before_short=short_count[i]; before_long=long_count[i];
            keys_n[i]=0; cycles(4); keys_n[i]=1; input_ms(6);
            if(short_count[i]!=before_short || long_count[i]!=before_long) $fatal(1,"bounce accepted");
            keys_n[i]=0; input_ms(6);
            if(short_count[i]!=before_short) $fatal(1,"short acted before release");
            keys_n[i]=1; input_ms(6);
            if(short_count[i]!=before_short+1 || long_count[i]!=before_long) $fatal(1,"short count %0d",i);
            keys_n[i]=0; input_ms(30); keys_n[i]=1; input_ms(6);
            if(short_count[i]!=before_short+1 || long_count[i]!=before_long+1) $fatal(1,"long exclusivity %0d",i);
        end
        before_short=short_count[0]; before_long=long_count[0];
        keys_n[0]=0; input_ms(6);
        test_consume=1; cycles(1); test_consume=0; input_ms(30);
        keys_n[0]=1; input_ms(6);
        if(short_count[0]!=before_short || long_count[0]!=before_long) $fatal(1,"consume replayed held key");
        keys_n[0]=0; input_ms(6); keys_n[0]=1; input_ms(6);
        if(short_count[0]!=before_short+1) $fatal(1,"consume prevented next press");
        enable=0; keys_n[1]=0; input_ms(6); enable=1; input_ms(20);
        before_short=short_count[1]; keys_n[1]=1; input_ms(6);
        if(short_count[1]!=before_short) $fatal(1,"disabled press replayed");
        sw3=0; input_ms(6); sw3=1; input_ms(6);
        if(!exam_request || fire_request) $fatal(1,"independent SW3 guard");
        sw4=0; input_ms(6); sw4=1; input_ms(6);
        if(!exam_request || !fire_request) $fatal(1,"independent SW4 guard");
        sw1=1; input_ms(6);
        if(!music_mute) $fatal(1,"SW1 mute not sampled");
        $fdisplay(result_file,"PASS all three keys: bounce, release-only short, one long, consume/enable release guard; independent SW boot guards");

        reset_proc();
        before_short=resolution_count;key1_event_proc();cycles(100);
        if(resolution_count!=before_short+1)$fatal(1,"ordinary K1 resolution event");
        event_proc(0,2);before_short=resolution_count;key1_event_proc();cycles(100);
        if(page_group!=2 || resolution_count!=before_short+1)$fatal(1,"timetable K1 resolution event");
        test_exam=1;cycles(4);before_short=resolution_count;key1_event_proc();cycles(100);
        if(resolution_count!=before_short)$fatal(1,"exam page emitted resolution toast");
        test_exam=0;cycles(4);test_fire=1;cycles(4);before_short=resolution_count;
        key1_event_proc();cycles(100);
        if(resolution_count!=before_short)$fatal(1,"fire page emitted resolution toast");
        test_fire=0;cycles(4);
        $fdisplay(result_file,"PASS K1 resolution prompt includes timetable and excludes exam/fire/menu");

        reset_proc();
        if(!auto_mode || temporary_pause) $fatal(1,"boot is not automatic");
        tick_proc(4);
        if(player_busy) $fatal(1,"auto dwell too short");
        tick_proc(1);
        if(!player_busy || requested_index!=1) $fatal(1,"external auto request missing");
        tick_proc(20);
        if(requested_index!=1) $fatal(1,"auto stacked while reader busy");
        commit_proc();
        tick_proc(3);
        commit_proc();
        tick_proc(2);
        if(!player_busy || requested_index!=2) $fatal(1,"same-image frame commits reset auto dwell");
        commit_proc();
        event_proc(1,0); commit_proc(); event_proc(4,0);
        valid_mask[2]=0;
        event_proc(2,0);
        cycles(8);
        if(auto_mode || !temporary_pause || !player_busy || requested_index!=3 || player_error)
            $fatal(1,"invalid target was not skipped in one request");
        commit_proc();
        tick_proc(9);
        if(!temporary_pause) $fatal(1,"pause expired early");
        event_proc(1,0); cycles(12);
        if(!temporary_pause) $fatal(1,"flip did not reset pause");
        if(player_busy) commit_proc();
        tick_proc(9);
        if(!temporary_pause) $fatal(1,"restarted pause too short");
        tick_proc(1);
        if(temporary_pause || !auto_mode) $fatal(1,"pause did not restore automatic");
        event_proc(4,0);
        if(!temporary_pause || auto_mode) $fatal(1,"K4 pause");
        event_proc(4,0);
        if(temporary_pause || !auto_mode) $fatal(1,"K4 immediate resume");
        $fdisplay(result_file,"PASS actual ten-image player: auto dwell/commit, immediate invalid-target skip, temporary pause restart/timeout, K4 resume");

        reset_proc();
        active_index=3;
        select_group(10'b0000001110,4'd3);
        check_no_error=1;
        event_proc(2,0);
        wait(player_busy && requested_index==1);
        if(player_error) $fatal(1,"notice group forward wrap reported an error");
        commit_proc();
        event_proc(1,0);
        wait(player_busy && requested_index==3);
        if(player_error) $fatal(1,"notice group backward wrap reported an error");
        commit_proc();
        check_no_error=0;
        valid_mask[2]=0;
        event_proc(1,0);
        wait(player_busy && requested_index==1);
        if(player_error) $fatal(1,"reverse bad-file skip failed");
        commit_proc();
        event_proc(2,0);
        wait(player_busy && requested_index==3);
        if(player_error) $fatal(1,"forward bad-file skip failed");
        commit_proc();
        $fdisplay(result_file,"PASS notice group forward/backward wrap and one-press bad-file skip in both directions");

        reset_proc();
        active_index=2;
        select_group(10'b0000001110,4'd2);
        check_no_error=1;
        event_proc(2,0);
        if(!player_busy || requested_index!=3) $fatal(1,"delayed-invalid fixture request missing");
        check_no_error=0;
        valid_mask[3]=0;
        wait(player_error==8'he5);
        wait(player_busy && requested_index==1);
        if(player_error) $fatal(1,"delayed invalid file was not cleared after skipping without another key");
        commit_proc();
        $fdisplay(result_file,"PASS in-flight invalidation resumes original direction and skips group boundary without E5");

        reset_proc();
        active_index=8;
        select_group(10'h100,4'd8);
        commit_proc();
        @(negedge clk);selection_mask=10'h00e;
        @(negedge clk);
        if(requested_index!=1 || !player_busy)
            $fatal(1,"scene target overwritten by idle cleanup: requested=%0d busy=%b",requested_index,player_busy);
        commit_proc();

        reset_proc();
        active_index=1;
        select_group(10'h00e,4'd1);
        commit_proc();
        @(negedge clk);test_short=1;
        @(negedge clk);test_short=0;
        wait(player_proc.search_flag);
        @(negedge clk);test_long=1;
        @(negedge clk);test_long=0;selection_mask=10'h0f0;target_index=4;target_valid=1;
        if(!consume_event || !player_proc.search_flag)$fatal(1,"scene/search collision fixture missing");
        @(negedge clk);target_valid=0;
        if(requested_index!=4 || !player_busy || player_proc.search_flag)
            $fatal(1,"consume cancelled the new scene target: requested=%0d busy=%b",requested_index,player_busy);
        commit_proc();
        $fdisplay(result_file,"PASS new scene/explicit targets take priority over idle correction and consumed old searches");

        reset_proc();
        event_proc(2,0);
        event_proc(1,0);
        if(!player_busy || !player_proc.manual_pending) $fatal(1,"busy queue fixture missing");
        event_proc(0,4);
        if(!menu_active || player_proc.manual_pending) $fatal(1,"menu did not consume queued navigation");
        commit_proc();
        if(player_busy) $fatal(1,"old queued navigation escaped into menu");
        before_short=resolution_count;key1_event_proc();
        if(resolution_count!=before_short)$fatal(1,"menu K1 leaked a resolution notice");
        if(menu_item!=7)$fatal(1,"menu K1 did not wrap upward");
        event_proc(1,0);
        if(menu_item!=0)$fatal(1,"menu K2 did not wrap downward");
        tick_proc(4);
        if(!menu_active || !temporary_pause) $fatal(1,"menu did not freeze pause");
        event_proc(2,0);
        if(music_volume!=3) $fatal(1,"menu volume minus");
        event_proc(4,0);
        if(music_volume!=4) $fatal(1,"menu volume plus");
        event_proc(1,0); event_proc(2,0);
        if(menu_item!=1 || brightness_level!=3) $fatal(1,"menu brightness state");
        event_proc(1,0); event_proc(4,0);
        if(menu_item!=2 || eye_mode!=1) $fatal(1,"menu warm mode");
        event_proc(4,0);event_proc(4,0);
        if(eye_mode!=2) $fatal(1,"eye mode upper bound");
        event_proc(1,0);event_proc(4,0);
        if(menu_item!=3 || slideshow_ms!=1005 || slideshow_seconds!=1) $fatal(1,"menu slideshow interval");
        event_proc(1,0);event_proc(4,0);
        if(menu_item!=4 || transition_mode!=1) $fatal(1,"menu transition mode");
        event_proc(4,0);event_proc(4,0);
        if(transition_mode!=2) $fatal(1,"transition mode upper bound");
        event_proc(2,0);event_proc(2,0);
        if(transition_mode!=0) $fatal(1,"transition mode lower bound");
        event_proc(2,0);
        if(transition_mode!=0) $fatal(1,"transition mode underflow");
        event_proc(1,0);
        if(menu_item!=5 || control_proc.subtitle_enable) $fatal(1,"subtitle menu/default");
        event_proc(4,0);event_proc(4,0);
        if(!control_proc.subtitle_enable) $fatal(1,"subtitle enable saturation");
        event_proc(2,0);event_proc(2,0);
        if(control_proc.subtitle_enable) $fatal(1,"subtitle disable saturation");
        event_proc(1,0);
        if(menu_item!=6 || subtitle_speed!=2)$fatal(1,"subtitle speed default");
        repeat(6)event_proc(4,0);
        if(subtitle_speed!=4)$fatal(1,"subtitle speed upper bound");
        repeat(6)event_proc(2,0);
        if(subtitle_speed!=0)$fatal(1,"subtitle speed lower bound");
        event_proc(1,0);
        if(menu_item!=7 || subtitle_alpha!=1)$fatal(1,"subtitle opacity default");
        repeat(6)event_proc(4,0);
        if(subtitle_alpha!=4)$fatal(1,"subtitle opacity upper bound");
        repeat(6)event_proc(2,0);
        if(subtitle_alpha!=0)$fatal(1,"subtitle opacity lower bound");
        event_proc(1,0);
        if(menu_item!=0)$fatal(1,"eight menu items wrap");
        tick_proc(5);
        if(menu_active || !temporary_pause) $fatal(1,"menu timeout lost saved pause");
        tick_proc(9);
        if(!temporary_pause) $fatal(1,"menu exit failed to restart pause");
        tick_proc(1);
        if(!auto_mode) $fatal(1,"menu return never resumed");
        event_proc(0,1);
        if(page_group!=1 || !auto_mode) $fatal(1,"culture first entry not auto");
        event_proc(4,0);
        event_proc(0,1);
        if(page_group!=0 || !auto_mode || !page_return_valid) $fatal(1,"notice state/image memory");
        event_proc(0,1);
        if(page_group!=1 || !temporary_pause) $fatal(1,"culture pause memory");
        event_proc(0,2);
        if(page_group!=2 || auto_mode) $fatal(1,"timetable not fixed");
        event_proc(1,0); event_proc(2,0); tick_proc(20);
        if(player_busy) $fatal(1,"timetable accepted navigation");
        event_proc(0,2);
        if(page_group!=1 || !temporary_pause) $fatal(1,"timetable return state");
        event_proc(0,2); event_proc(0,1);
        if(page_group!=0) $fatal(1,"K2 did not close timetable and switch group");
        $fdisplay(result_file,"PASS menu parameters/timeout/frozen timers, queue consumption, group state memory and timetable lock");

        reset_proc();
        event_proc(0,4);
        test_exam=1; cycles(6);
        if(menu_active || scene_mode!=1 || auto_mode || exam_running) $fatal(1,"exam menu preemption");
        for(i=1;i<=7;i=i+1) begin
            event_proc(2,0);
            if(exam_duration_index!=i%7) $fatal(1,"seven exam presets including demo and wrap");
            if(timer_seconds!=(i%7==6 ? 60 : (i%7+1)*1800))
                $fatal(1,"controller/timer preset mismatch: index=%0d seconds=%0d",exam_duration_index,timer_seconds);
        end
        repeat(6)event_proc(2,0);
        if(exam_duration_index!=6 || timer_seconds!=60)$fatal(1,"demo key selection did not load 01:00");
        event_proc(1,0);
        if(!exam_started || !exam_running || !timer_running || timer_seconds!=60) $fatal(1,"demo exam start");
        event_proc(2,0);
        if(exam_duration_index!=6 || timer_seconds!=60) $fatal(1,"duration changed after start");
        event_proc(0,1);
        if(exam_running || menu_active || page_group!=0) $fatal(1,"exam long key escaped ordinary action");
        event_proc(1,0);
        test_fire=1; cycles(6);
        if(scene_mode!=2 || exam_running) $fatal(1,"fire did not pause exam");
        event_proc(1,0); event_proc(2,0); event_proc(4,0);
        if(exam_running || !exam_started) $fatal(1,"fire failed to mask business keys");
        test_fire=0; cycles(6);
        if(scene_mode!=1 || exam_running) $fatal(1,"exam auto-resumed after fire");
        event_proc(1,0);
        before_short=finish_count; exam_done=1; cycles(8);
        if(!exam_finished || exam_running || finish_count!=before_short+1) $fatal(1,"exam finish one-shot");
        event_proc(1,0);
        if(exam_running) $fatal(1,"finished exam restarted without reset");
        exam_done=0; event_proc(4,0);
        if(exam_started || exam_finished || exam_running) $fatal(1,"exam reset state");
        if(timer_seconds!=60 || timer_running)$fatal(1,"demo controller/timer reset mismatch");
        test_exam=0; test_fire=1; cycles(6);
        test_exam=1; cycles(6); test_fire=0; cycles(6);
        if(exam_running || exam_started || scene_mode!=1) $fatal(1,"new exam during fire did not wait");
        test_exam=0; cycles(6);
        if(scene_mode!=0 || !auto_mode || menu_active) $fatal(1,"ordinary restore after emergency");
        $fdisplay(result_file,"PASS joint controller/timer seven-preset selection including 01:00, start/reset, finish-once, fire priority and new-exam wait");

        reset_proc();
        sw3=0; sw4=0; keys_n=7; input_ms(8); physical_mode=1; cycles(6);
        keys_n[1]=0; input_ms(6); keys_n[1]=1; input_ms(6);
        if(!temporary_pause || !player_busy || requested_index!=1)
            $fatal(1,"physical K3 to actual ten-image player integration");
        commit_proc();
        keys_n[2]=0; input_ms(20);
        if(!menu_active) $fatal(1,"physical K4 long to menu integration");
        keys_n[2]=1; input_ms(6);
        if(music_volume!=4) $fatal(1,"menu opening long leaked as plus");
        key1_n=0;input_ms(6);key1_n=1;input_ms(6);
        if(menu_item!=7 || resolution_notice)$fatal(1,"physical K1 did not select previous menu item exclusively");
        keys_n[0]=0;input_ms(6);keys_n[0]=1;input_ms(6);
        if(menu_item!=0)$fatal(1,"physical K2 did not select next menu item");
        sw4=1; input_ms(6);
        if(scene_mode!=2 || menu_active) $fatal(1,"physical SW4 to fire integration");
        $fdisplay(result_file,"PASS physical-key/switch to controller and ten-image player integration");

        physical_mode=0; test_mute=1; cycles(4);
        image_change=1; cycles(1); image_change=0;
        wait(cue_active); wait(!cue_active);
        cycles(1100);
        if(sample_data!==0 || audible_cue==0 || sample_seen<5)
            $fatal(1,"muted melody / audible cue / continuous sample clock");
        $fdisplay(result_file,"PASS SW1 melody mute preserves audible change cue and sample stream");
        $fdisplay(result_file,"PASS tb_photo_badge");
        $fclose(result_file); $finish;
    end
    initial begin #1000000; $fatal(1,"badge watchdog"); end
endmodule
