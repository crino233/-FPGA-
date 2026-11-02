`timescale 1ns/1ps
module photo_flash_model (
    input wire cs_n, input wire sclk, input wire mosi, output reg miso=1
);
    reg [7:0] memory [0:8191];
    reg [7:0] program_buf [0:15];
    reg [23:0] id_value=24'hef4017, address;
    reg [7:0] command, rx_byte, tx_byte;
    reg wel=0, protect_flag=0, cmp_flag=0, force_busy=0;
    reg ignore_wren=0, ignore_erase=0, ignore_program=0, corrupt_program=0;
    integer bit_count=0, byte_count=0, address_count=0, data_count=0;
    integer erase_count=0, program_count=0, wake_count=0;
    integer corrupt_index=5;
    time busy_until=0, last_cs_high=0;
    function bit busy_proc;
        busy_proc=force_busy || $time<busy_until;
    endfunction
    task clear_proc;
        begin
            for(integer i=0;i<8192;i=i+1)memory[i]=8'hff;
            wel=0; protect_flag=0; cmp_flag=0; force_busy=0;
            ignore_wren=0; ignore_erase=0; ignore_program=0; corrupt_program=0;
            busy_until=0; id_value=24'hef4017; corrupt_index=5;
        end
    endtask
    initial clear_proc();
    always @(negedge cs_n) begin
        if($time-last_cs_high<64)$fatal(1,"Flash CS high gap too short");
        bit_count=0; byte_count=0; address_count=0; data_count=0;
        rx_byte=0; tx_byte=8'hff; command=0; address=0; miso=1;
    end
    always @(posedge sclk) if(!cs_n)begin
        rx_byte={rx_byte[6:0],mosi};
        if(bit_count==7)begin
            bit_count=0;
            if(byte_count==0)begin
                command=rx_byte;
                case(command)
                    8'hab:begin wake_count=wake_count+1;tx_byte=8'hff;end
                    8'h9f:begin
                        if(busy_proc())$fatal(1,"JEDEC requested before retained Flash WIP cleared");
                        tx_byte=id_value[23:16];
                    end
                    8'h05:tx_byte={3'd0,protect_flag ? 3'b111 : 3'b000,wel,busy_proc()};
                    8'h35:tx_byte={1'b0,cmp_flag,6'd0};
                    8'h04,8'h06,8'h03,8'h20,8'h02:tx_byte=8'hff;
                    default:$fatal(1,"unexpected/prohibited Flash command %h",command);
                endcase
            end else case(command)
                8'h9f:tx_byte=byte_count==1 ? id_value[15:8] : id_value[7:0];
                8'h05:tx_byte={3'd0,protect_flag ? 3'b111 : 3'b000,wel,busy_proc()};
                8'h35:tx_byte={1'b0,cmp_flag,6'd0};
                8'h03,8'h20,8'h02:begin
                    if(address_count<3)begin
                        address={address[15:0],rx_byte}; address_count=address_count+1;
                        if(address_count==3)begin
                            if(address<24'h7fe000 || address>24'h7ffff0 || address[11:0]!=0)
                                $fatal(1,"Flash address escaped reserved aligned slots: %h",address);
                            if(command==8'h03)tx_byte=memory[address-24'h7fe000];
                        end
                    end else if(command==8'h03)begin
                        data_count=data_count+1;
                        tx_byte=memory[address-24'h7fe000+data_count];
                    end else if(command==8'h02)begin
                        if(data_count>=16)$fatal(1,"program exceeds fixed record");
                        program_buf[data_count]=rx_byte; data_count=data_count+1;
                    end
                end
            endcase
            byte_count=byte_count+1; rx_byte=0;
        end else bit_count=bit_count+1;
    end
    always @(negedge sclk) if(!cs_n)miso=tx_byte[7-bit_count];
    always @(posedge cs_n)begin
        last_cs_high=$time; miso=1;
        if(command==8'h06 && !busy_proc() && !ignore_wren)wel=1;
        if(command==8'h04 && !busy_proc())wel=0;
        if(command==8'h20 && address_count==3 && wel && !busy_proc() && !protect_flag && !cmp_flag)begin
            erase_count=erase_count+1;
            if(!ignore_erase)begin
                for(integer i=0;i<4096;i=i+1)memory[address-24'h7fe000+i]=8'hff;
                busy_until=$time+4000;
            end
            wel=0;
        end
        if(command==8'h02 && address_count==3 && data_count>0 && wel && !busy_proc() && !protect_flag && !cmp_flag)begin
            program_count=program_count+1;
            if(!ignore_program)begin
                for(integer i=0;i<data_count;i=i+1)
                    memory[address-24'h7fe000+i]=memory[address-24'h7fe000+i]&program_buf[i];
                if(corrupt_program)memory[address-24'h7fe000+corrupt_index]=memory[address-24'h7fe000+corrupt_index]^8'h01;
                busy_until=$time+2000;
            end
            wel=0;
        end
    end
endmodule

module tb_photo_config_flash #(parameter integer accept_delays=0,prove_lost=0,flash_spi_div=1,stable_delay_test=0);
    reg clk=0,rst_n=0,tick_1ms=0;
    always #4 clk=~clk;
    reg manual_mode=0,manual_menu=0,control_enable=0,exam_request=0;
    reg [25:0] manual_data={1'b0,2'd0,1'b0,2'd0,3'd0,5'd5,3'd4,3'd4};
    reg [2:0] short_event=0,long_event=0;
    reg inject_apply=0;
    reg [25:0] inject_data=0;
    wire menu_active;
    wire [2:0] volume,brightness,exam_index;
    wire [4:0] seconds;
    wire [15:0] milliseconds;
    wire exam_started,exam_running,auto_mode;
    wire [1:0] page_group;
    wire config_apply,ready,busy,saved;
    wire [25:0] config_data;
    wire subtitle_enable;
    wire [1:0] eye_mode;
    wire [1:0] transition_mode;
    wire [2:0] subtitle_speed,subtitle_alpha;
    wire [7:0] error_code;
    wire cs_n,sclk,mosi,miso,wp_n,hold_n;
    wire [25:0] control_data={subtitle_alpha,subtitle_speed,subtitle_enable,transition_mode,1'b0,eye_mode,exam_index,seconds,brightness,volume};
    wire [25:0] live_data=manual_mode ? manual_data : control_data;
    integer result_file,apply_count=0,saved_count=0,before_erases,before_saves;
    integer store_accept_count=0,byte_accept_count=0;
    wire store_accept_gate=!accept_delays || dut.store_operation!=2 || store_accept_count>=4;
    wire byte_accept_gate=!accept_delays || byte_accept_count>=4;
    string test_name;
    reg invalid_state_injection=0;
    always @(posedge clk)begin
        if(!rst_n)begin store_accept_count<=0;byte_accept_count<=0;end
        else begin
            if(!dut.store_start)store_accept_count<=0;
            else if(store_accept_count<4)store_accept_count<=store_accept_count+1;
            if(!dut.store_proc.byte_start)byte_accept_count<=0;
            else if(byte_accept_count<4)byte_accept_count<=byte_accept_count+1;
        end
    end
    reg [127:0] record_a,record_b,bad_record;
    localparam [25:0] defaults={3'd1,3'd2,1'b0,2'd0,1'b0,2'd0,3'd0,5'd5,3'd4,3'd4};
    localparam [25:0] value_a={3'd3,3'd4,1'b0,2'd2,1'b0,2'd1,3'd3,5'd12,3'd2,3'd1};
    localparam [25:0] value_b={3'd0,3'd1,1'b0,2'd0,1'b0,2'd2,3'd5,5'd30,3'd0,3'd4};
    localparam [25:0] value_c={3'd4,3'd0,1'b0,2'd1,1'b0,2'd0,3'd0,5'd1,3'd4,3'd0};
    localparam [25:0] value_demo={3'd1,3'd2,1'b0,2'd2,1'b0,2'd1,3'd6,5'd12,3'd2,3'd1};
    photo_config_flash #(.save_delay_ms(stable_delay_test ? 1000 : 3),.spi_div(flash_spi_div),.startup_cycles(16),
        .wake_cycles(4),.poll_cycles(8),.timeout_cycles(20000)) dut(
        .clk(clk),.rst_n(rst_n),.tick_1ms(tick_1ms),
        .menu_active(manual_mode ? manual_menu : menu_active),.live_data(live_data),
        .config_apply(config_apply),.config_data(config_data),.ready(ready),.busy(busy),
        .saved(saved),.error_code(error_code),.flash_cs_n(cs_n),.flash_sclk(sclk),
        .flash_mosi(mosi),.flash_miso(miso),.flash_wp_n(wp_n),.flash_hold_n(hold_n)
    );
    photo_flash_model flash_proc(.cs_n(cs_n),.sclk(sclk),.mosi(mosi),.miso(miso));
    photo_badge_control #(.menu_timeout_ms(5)) control_proc(
        .clk(clk),.rst_n(rst_n),.enable(control_enable),.tick_1ms(tick_1ms),
        .short_event(short_event),.long_event(long_event),.key1_short_event(1'b0),.exam_request(exam_request),
        .fire_request(1'b0),.music_mute(1'b0),.player_busy(1'b0),.frame_commit(1'b0),
        .active_index(4'd1),.exam_done(1'b0),
        .config_apply(config_apply || inject_apply),.config_data(inject_apply ? inject_data : config_data),
        .player_next_down(),.player_prev_down(),.player_auto_step(),.auto_mode(auto_mode),
        .consume_event(),.temporary_pause(),.page_group(page_group),.page_change(),
        .page_return_index(),.page_return_valid(),.page_select_valid(),.page_select_index(),
        .menu_active(menu_active),.menu_item(),.menu_adjust(),.music_volume(volume),
        .eye_mode(eye_mode),.subtitle_speed(subtitle_speed),.subtitle_alpha(subtitle_alpha),.transition_mode(transition_mode),
        .subtitle_enable(subtitle_enable),
        .brightness_level(brightness),.slideshow_ms(milliseconds),.slideshow_seconds(seconds),
        .exam_start_toggle(),.exam_duration_step(),.exam_reset(),.exam_pause(),.exam_finish(),
        .exam_started(exam_started),.exam_running(exam_running),.exam_finished(),
        .exam_duration_index(exam_index),.music_enable(),.scene_mode()
    );
    always @(negedge clk) if(rst_n)begin
        if(!invalid_state_injection && (!$onehot(dut.state) || !$onehot(dut.store_proc.state)))
            $fatal(1,"Flash control state lost one-hot encoding");
        if(config_apply)apply_count=apply_count+1;
        if(saved)saved_count=saved_count+1;
        if(wp_n!==1 || hold_n!==1)$fatal(1,"Flash WP/HOLD not safely inactive");
        if(dut.store_start && dut.store_operation==2 && dut.stored_valid && dut.slot==dut.active_slot)
            $fatal(1,"attempt to erase currently active record");
        if(dut.state[dut.st_read_wait] && dut.store_valid && dut.crc_busy)
            $fatal(1,"next Flash byte arrived before the serial CRC consumed the previous byte");
    end
    function automatic [15:0] crc_proc(input [111:0] data);
        reg [15:0] check;
        begin
            check=16'hffff;
            for(integer i=0;i<14;i=i+1)begin
                check=check^({8'd0,data[111-i*8-:8]}<<8);
                for(integer j=0;j<8;j=j+1)check=check[15] ? (check<<1)^16'h1021 : check<<1;
            end
            crc_proc=check;
        end
    endfunction
    function automatic [127:0] record_proc(input [31:0] version,input [25:0] data);
        reg [127:0] word_data;
        begin
            word_data={32'h42470510,version,5'd0,data[2:0],5'd0,data[5:3],
                3'd0,data[10:6],5'd0,data[13:11],3'd0,data[19],data[18:17],data[15:14],2'd0,data[25:23],data[22:20],16'd0};
            word_data[15:0]=crc_proc(word_data[127:16]); record_proc=word_data;
        end
    endfunction
    function automatic [127:0] legacy_record_proc(input [31:0] version,input [7:0] format,input [25:0] data);
        reg [127:0] word_data;
        begin
            word_data=record_proc(version,data);
            word_data[111:104]=format;
            word_data[23:16]=format==1 ? 0 : 1;
            if(format==1)word_data[31:24]=0;
            else if(format==2)word_data[31:26]=0;
            else if(format==3)word_data[31:28]=0;
            word_data[15:0]=crc_proc(word_data[127:16]);
            legacy_record_proc=word_data;
        end
    endfunction
    task install_proc(input bit slot,input [127:0] data);
        for(integer i=0;i<16;i=i+1)flash_proc.memory[slot*4096+i]=data[127-i*8-:8];
    endtask
    function automatic [127:0] stored_proc(input bit slot);
        reg [127:0] data;
        begin
            for(integer i=0;i<16;i=i+1)data[127-i*8-:8]=flash_proc.memory[slot*4096+i];
            stored_proc=data;
        end
    endfunction
    task cycles_proc(input integer count);
        repeat(count)@(negedge clk);
    endtask
    task reset_proc;
        begin
            @(negedge clk);rst_n=0;tick_1ms=0;manual_menu=0;manual_data=defaults;
            control_enable=0;exam_request=0;short_event=0;long_event=0;inject_apply=0;
            cycles_proc(4);rst_n=1;cycles_proc(4);
        end
    endtask
    task boot_proc;
        begin
            reset_proc();wait(ready && !busy);cycles_proc(4);
            if(error_code)$fatal(1,"boot failed code=%h",error_code);
        end
    endtask
    task ticks_proc(input integer count);
        begin
            repeat(count)begin
                @(negedge clk);tick_1ms=1;@(negedge clk);tick_1ms=0;cycles_proc(3);
            end
        end
    endtask
    task event_proc(input [2:0] short_value,input [2:0] long_value);
        begin
            @(negedge clk);short_event=short_value;long_event=long_value;
            @(negedge clk);short_event=0;long_event=0;cycles_proc(5);
        end
    endtask
    task save_proc(input [25:0] data);
        begin
            @(negedge clk);manual_data=data;cycles_proc(4);ticks_proc(3);
            wait(saved || error_code!=0);cycles_proc(3);
            if(error_code || dut.saved_data!==data)$fatal(1,"save failed code=%h",error_code);
        end
    endtask
    task fault_proc(input [7:0] expected_code);
        begin
            wait(error_code!=0);cycles_proc(5);
            if(error_code!==expected_code || !ready || busy)$fatal(1,"fault code=%h expected=%h",error_code,expected_code);
        end
    endtask
    initial begin
        test_name=stable_delay_test ? "tb_photo_flash_stable" : prove_lost ? "tb_photo_flash_lost_request" : accept_delays ? "tb_photo_flash_accept" :
            flash_spi_div==8 ? "tb_photo_flash_production" : "tb_photo_config_flash";
        result_file=$fopen({test_name,".result"},"w");
        if(prove_lost)begin
            manual_mode=1;boot_proc();manual_data=value_a;cycles_proc(4);ticks_proc(3);cycles_proc(1000);
            if(!busy || dut.store_busy || error_code || saved_count!=0)
                $fatal(1,"old lost save request not reproduced");
            $fdisplay(result_file,"PASS old write request lost: whole settings save stranded, lower Flash idle, no timeout or error; prior record unchanged");
            $fdisplay(result_file,"PASS tb_photo_flash_lost_request");$fclose(result_file);$finish;
        end
        if(stable_delay_test)begin
            manual_mode=1;boot_proc();manual_menu=1;manual_data=value_a;cycles_proc(4);ticks_proc(999);
            if(busy || flash_proc.erase_count || saved_count)$fatal(1,"saved before 1000 stable ticks in menu");
            manual_data=value_b;cycles_proc(4);ticks_proc(999);
            if(busy || flash_proc.erase_count || saved_count)$fatal(1,"edit did not restart full stability delay");
            manual_menu=0;ticks_proc(1);
            if(!busy || dut.snapshot_data!==value_b)$fatal(1,"1000th stable tick did not launch latest snapshot");
            manual_data=value_c;manual_menu=1;cycles_proc(4);
            wait(saved || error_code);cycles_proc(4);
            if(error_code || dut.saved_data!==value_b || stored_proc(0)!==record_proc(1,value_b))
                $fatal(1,"busy edit changed the accepted save snapshot");
            before_erases=flash_proc.erase_count;ticks_proc(999);
            if(busy || flash_proc.erase_count!=before_erases)$fatal(1,"pending busy edit saved before stable delay");
            ticks_proc(1);wait(saved || error_code);cycles_proc(4);
            if(error_code || !manual_menu || dut.saved_data!==value_c || stored_proc(1)!==record_proc(2,value_c))
                $fatal(1,"stable latest edit was not saved with menu still open");
            before_erases=flash_proc.erase_count;before_saves=saved_count;manual_menu=0;ticks_proc(1100);
            if(busy || saved_count!=before_saves || flash_proc.erase_count!=before_erases)
                $fatal(1,"menu close or unchanged data repeated a save");
            boot_proc();if(config_data!==value_c)$fatal(1,"verified menu save did not restore");
            manual_data=value_a;cycles_proc(4);ticks_proc(999);boot_proc();
            if(config_data!==value_c)$fatal(1,"reset before stability lost the previous valid record");
            $fdisplay(result_file,"PASS production 1000 stable ticks: edit resets delay, menu close keeps progress, save completes while menu open, immutable busy snapshot/latest edit, no duplicate erase and reset recovery");
            $fdisplay(result_file,"INFO millisecond strobes accelerated; pin-level behavioral Flash, no board latency measurement");
            $fdisplay(result_file,"PASS %s",test_name);$fclose(result_file);$finish;
        end
        manual_mode=0;boot_proc();before_erases=flash_proc.erase_count;ticks_proc(20);
        if(control_data!==defaults || apply_count!=0 || flash_proc.erase_count!=before_erases)
            $fatal(1,"blank Flash did not retain defaults without writes");
        control_enable=1;cycles_proc(5);event_proc(0,4);event_proc(2,0);
        event_proc(1,0);event_proc(2,0);event_proc(1,0);event_proc(1,0);event_proc(4,0);
        event_proc(1,0);event_proc(4,0);
        event_proc(1,0);event_proc(4,0);
        event_proc(1,0);event_proc(4,0);
        event_proc(1,0);event_proc(4,0);
        if(volume!=3 || brightness!=3 || seconds!=6 || milliseconds!=6000 || transition_mode!=1 || !menu_active)
            $fatal(1,"real menu parameter integration");
        if(!subtitle_enable || subtitle_speed!=3 || subtitle_alpha!=2)$fatal(1,"subtitle menu settings");
        if(flash_proc.erase_count!=before_erases)$fatal(1,"continuous edits erased before stable delay");
        ticks_proc(3);wait(saved);cycles_proc(4);
        if(!menu_active)$fatal(1,"real menu save waited for menu close");
        record_a=record_proc(1,control_data);
        if(stored_proc(0)!==record_a)$fatal(1,"record layout/CRC differs from independent reference");
        boot_proc();
        if(volume!=3 || brightness!=3 || seconds!=6 || milliseconds!=6000 || transition_mode!=1 ||
            !subtitle_enable || menu_active || page_group!=0 || exam_started)
            $fatal(1,"real controller boot restore changed transient state");
        $fdisplay(result_file,"PASS real menu -> stable save while still open -> FPGA reset -> coherent restore; blank Flash keeps defaults without erase");

        flash_proc.clear_proc();install_proc(0,legacy_record_proc(17,8'h01,value_a));boot_proc();
        if(config_data!=={3'd1,3'd2,6'd0,value_a[13:0]} || eye_mode!=0 || transition_mode!=0)
            $fatal(1,"v1 default extensions");
        manual_mode=1;save_proc(value_a);boot_proc();
        if(config_data!==value_a || subtitle_speed!=4 || subtitle_alpha!=3)$fatal(1,"v1 to v5 upgrade");
        save_proc(value_demo);boot_proc();
        if(config_data!==value_demo || control_data!==value_demo || exam_index!=6 || exam_started)$fatal(1,"demo restore");
        install_proc(!dut.active_slot,record_proc(20,{value_demo[25:14],3'd7,value_demo[10:0]}));
        boot_proc();if(config_data!==value_demo)$fatal(1,"invalid exam index accepted");
        install_proc(!dut.active_slot,record_proc(21,{value_demo[25:19],2'd3,value_demo[16:0]}));
        boot_proc();if(config_data!==value_demo)$fatal(1,"invalid transition accepted");
        install_proc(!dut.active_slot,legacy_record_proc(22,8'h01,value_demo));
        boot_proc();if(config_data!==value_demo)$fatal(1,"v1 accepted index 6");
        flash_proc.clear_proc();install_proc(0,legacy_record_proc(23,8'h02,value_a));boot_proc();
        if(config_data!=={3'd1,3'd2,4'd0,value_a[15:0]} || transition_mode!=0 || eye_mode!=1)$fatal(1,"v2 compatibility");
        bad_record=legacy_record_proc(24,8'h02,value_a);bad_record[26]=1;
        bad_record[15:0]=crc_proc(bad_record[127:16]);install_proc(1,bad_record);boot_proc();
        if(config_data!=={3'd1,3'd2,4'd0,value_a[15:0]})$fatal(1,"v2 reserved transition bit");
        flash_proc.clear_proc();install_proc(0,legacy_record_proc(30,8'h03,value_a));boot_proc();
        if(config_data!=={3'd1,3'd2,1'b0,value_a[18:0]} || subtitle_enable)$fatal(1,"v3 defaults");
        bad_record=legacy_record_proc(31,8'h03,value_a);bad_record[28]=1;
        bad_record[15:0]=crc_proc(bad_record[127:16]);install_proc(1,bad_record);boot_proc();
        if(config_data!=={3'd1,3'd2,1'b0,value_a[18:0]})$fatal(1,"v3 accepted subtitle reserved bit");
        flash_proc.clear_proc();install_proc(0,legacy_record_proc(40,8'h04,value_c|26'h80000));boot_proc();
        if(config_data!=={3'd1,3'd2,1'b1,value_c[18:0]} || !subtitle_enable || subtitle_speed!=2 || subtitle_alpha!=1)
            $fatal(1,"v4 subtitle/default speed/opacity");
        manual_mode=1;save_proc(value_a|26'h80000);boot_proc();
        if(config_data!==(value_a|26'h80000) || !subtitle_enable)$fatal(1,"v5 settings persistence");
        for(integer field=0;field<2;field=field+1)begin
            bad_record=record_proc(42,value_a);
            bad_record[23:16]=field ? 8'h28 : 8'h05;
            bad_record[15:0]=crc_proc(bad_record[127:16]);install_proc(!dut.active_slot,bad_record);boot_proc();
            if(config_data!==(value_a|26'h80000))$fatal(1,"invalid subtitle setting field");
        end
        $fdisplay(result_file,"PASS v1/v2/v3/v4 strict compatibility, old flash-speed ignored, default subtitle speed/opacity, v5 persistence and range rejection; exam indices preserved");
        manual_mode=0;

        flash_proc.clear_proc();install_proc(0,record_proc(9,value_a));
        reset_proc();control_enable=1;cycles_proc(5);event_proc(0,4);event_proc(2,0);
        wait(ready && !busy);cycles_proc(5);
        if(volume!=3 || brightness!=4 || seconds!=5 || exam_index!=0)
            $fatal(1,"late Flash load overwrote a user adjustment");
        @(negedge clk);inject_data=value_b;inject_apply=1;short_event=2;
        @(negedge clk);inject_apply=0;short_event=0;cycles_proc(4);
        if(volume!=2)$fatal(1,"same-cycle restore defeated menu operation");
        reset_proc();control_enable=1;exam_request=1;cycles_proc(8);event_proc(1,0);
        inject_data=value_b;inject_apply=1;cycles_proc(1);inject_apply=0;cycles_proc(3);
        if(!exam_started || !exam_running || control_data!==defaults)
            $fatal(1,"restore changed a running exam");
        $fdisplay(result_file,"PASS late/same-cycle restore respects newer user edits and never restores a running exam");

        manual_mode=1;flash_proc.clear_proc();
        install_proc(0,record_proc(32'hffffffff,value_a));install_proc(1,record_proc(0,value_b));
        boot_proc();
        if(config_data!==value_b || dut.active_slot!=1 || control_data!==value_b || milliseconds!=30000)
            $fatal(1,"version wrap/four-parameter controller restore");
        bad_record=record_proc(1,value_c);bad_record[0]=!bad_record[0];install_proc(1,bad_record);
        boot_proc();if(config_data!==value_a || dut.active_slot!=0)$fatal(1,"bad CRC fallback");
        install_proc(1,record_proc(1,{2'd0,1'b1,2'd3,3'd7,5'd0,3'd7,3'd7}));
        boot_proc();if(config_data!==value_a)$fatal(1,"valid CRC invalid fields accepted");
        install_proc(0,{128{1'b1}});boot_proc();
        if(dut.stored_valid || config_apply)$fatal(1,"invalid slots exposed configuration");
        before_erases=flash_proc.erase_count;ticks_proc(20);
        if(flash_proc.erase_count!=before_erases)$fatal(1,"corrupt defaults auto-erased");
        $fdisplay(result_file,"PASS independent CRC/layout, dual-slot newest selection including wrap, corrupt/invalid-field fallback");

        flash_proc.clear_proc();record_a=record_proc(32'h12345678,value_a);install_proc(0,record_a);
        record_b=record_proc(32'h12345679,value_b);
        for(integer bit_index=0;bit_index<128;bit_index=bit_index+1)begin
            bad_record=record_b;bad_record[bit_index]=!bad_record[bit_index];install_proc(1,bad_record);
            boot_proc();
            if(config_data!==value_a || dut.active_slot!=0)$fatal(1,"accepted bit corruption at %0d",bit_index);
        end
        for(integer byte_index=0;byte_index<14;byte_index=byte_index+1)begin
            if(byte_index<4 || byte_index>=8)begin
                bad_record=record_b;bad_record[127-byte_index*8-:8]=8'hff;
                bad_record[15:0]=crc_proc(bad_record[127:16]);install_proc(1,bad_record);
                boot_proc();
                if(config_data!==value_a)$fatal(1,"accepted invalid format/range byte %0d with valid CRC",byte_index);
            end
        end
        $fdisplay(result_file,"PASS all 128 single-bit record corruptions rejected; header/range/reserved-byte checks reject recomputed valid CRC");

        flash_proc.clear_proc();boot_proc();before_erases=flash_proc.erase_count;
        manual_menu=1;manual_data=value_a;cycles_proc(4);ticks_proc(2);
        if(flash_proc.erase_count!=before_erases)$fatal(1,"unstable menu edit started erase");
        manual_data=defaults;cycles_proc(4);ticks_proc(5);
        if(flash_proc.erase_count!=before_erases)$fatal(1,"changed-back value caused erase");
        save_proc(value_a);before_erases=flash_proc.erase_count;ticks_proc(20);
        if(flash_proc.erase_count!=before_erases)$fatal(1,"unchanged values repeatedly saved");
        manual_data=value_b;cycles_proc(4);ticks_proc(3);
        wait(dut.store_proc.status_phase==2 && dut.store_proc.busy);manual_data=value_c;manual_menu=1;
        wait(saved);cycles_proc(4);
        if(dut.saved_data!==value_b || stored_proc(1)!==record_proc(2,value_b))$fatal(1,"in-flight save payload changed");
        before_erases=flash_proc.erase_count;ticks_proc(2);
        if(flash_proc.erase_count!=before_erases)$fatal(1,"busy edit escaped stability delay");
        ticks_proc(1);wait(saved);cycles_proc(4);
        if(dut.saved_data!==value_c || stored_proc(0)!==record_proc(3,value_c))$fatal(1,"latest busy change lost");
        if(!manual_menu)$fatal(1,"latest busy save waited for menu close");
        boot_proc();if(config_data!==value_c)$fatal(1,"newest busy save failed reboot");
        $fdisplay(result_file,"PASS menu-open stability/changed-back/no-op suppression, immutable save snapshot and latest busy update");

        for(integer cut=0;cut<=16;cut=cut+1)begin
            flash_proc.clear_proc();record_a=record_proc(5,value_a);install_proc(0,record_a);boot_proc();
            manual_data=value_b;cycles_proc(4);ticks_proc(3);
            wait(flash_proc.command==8'h02 && flash_proc.address_count==3 && flash_proc.data_count==cut && !cs_n);
            boot_proc();
            if(stored_proc(0)!==record_a || config_data!==(cut==16 ? value_b : value_a))
                $fatal(1,"power-cut recovery failed after %0d bytes",cut);
        end
        $fdisplay(result_file,"PASS FPGA reset at 0..16 programmed bytes: old valid slot retained; complete new record recovered; WIP/WEL survive reset");

        flash_proc.clear_proc();flash_proc.id_value=24'hffffff;reset_proc();fault_proc(8'hc1);
        control_enable=1;cycles_proc(5);event_proc(0,4);event_proc(2,0);
        if(!menu_active || volume!=3)$fatal(1,"Flash fault blocked normal controls");
        for(integer id_index=0;id_index<3;id_index=id_index+1)begin
            flash_proc.clear_proc();flash_proc.id_value=24'hef4017^(24'h1<<(id_index*8));
            reset_proc();fault_proc(8'hc1);
        end
        flash_proc.clear_proc();flash_proc.protect_flag=1;reset_proc();fault_proc(8'hc2);
        flash_proc.clear_proc();flash_proc.cmp_flag=1;reset_proc();fault_proc(8'hc2);
        flash_proc.clear_proc();flash_proc.force_busy=1;reset_proc();fault_proc(8'hc6);
        flash_proc.clear_proc();boot_proc();flash_proc.ignore_wren=1;manual_data=value_a;
        cycles_proc(4);ticks_proc(3);fault_proc(8'hc3);
        flash_proc.clear_proc();install_proc(0,record_proc(1,value_a));
        for(integer i=4096;i<8192;i=i+1)flash_proc.memory[i]=0;
        boot_proc();flash_proc.ignore_erase=1;manual_data=value_b;cycles_proc(4);ticks_proc(3);fault_proc(8'hc4);
        flash_proc.clear_proc();install_proc(0,record_proc(1,value_a));boot_proc();
        flash_proc.ignore_program=1;manual_data=value_b;cycles_proc(4);ticks_proc(3);fault_proc(8'hc5);
        flash_proc.clear_proc();install_proc(0,record_proc(1,value_a));boot_proc();
        flash_proc.corrupt_program=1;manual_data=value_b;cycles_proc(4);ticks_proc(3);fault_proc(8'hc5);
        flash_proc.corrupt_program=0;boot_proc();if(config_data!==value_a)$fatal(1,"verify failure lost prior config");
        for(integer byte_index=0;byte_index<16;byte_index=byte_index+1)begin
            flash_proc.clear_proc();install_proc(0,record_proc(1,value_a));
            flash_proc.memory[4096+byte_index]=0;
            boot_proc();flash_proc.ignore_erase=1;manual_data=value_b;
            cycles_proc(4);ticks_proc(3);fault_proc(8'hc4);
            flash_proc.clear_proc();install_proc(0,record_proc(1,value_a));boot_proc();
            flash_proc.corrupt_program=1;flash_proc.corrupt_index=byte_index;manual_data=value_b;
            cycles_proc(4);ticks_proc(3);fault_proc(8'hc5);
            flash_proc.corrupt_program=0;boot_proc();
            if(config_data!==value_a)$fatal(1,"readback mismatch at byte %0d lost prior record",byte_index);
        end
        flash_proc.clear_proc();boot_proc();
        @(negedge clk);invalid_state_injection=1;force dut.state=14'd0;
        @(negedge clk);release dut.state;fault_proc(8'hcf);
        flash_proc.clear_proc();reset_proc();
        @(negedge clk);force dut.store_proc.state=14'd0;
        @(negedge clk);release dut.store_proc.state;fault_proc(8'hcf);
        $fdisplay(result_file,"PASS wrong ID/protection/CMP/busy timeout/WEL/erase/readback faults are bounded and nonblocking; prior record survives");
        $fdisplay(result_file,"PASS all three JEDEC bytes checked, erase/readback failures detected at all 16 byte offsets, upper/lower invalid states report CF");
        $fdisplay(result_file,"INFO pin-level behavioral Flash only; no physical Flash writes or hardware validation");
        $fdisplay(result_file,"PASS %s",test_name);$fclose(result_file);$finish;
    end
    initial begin #50000000;$fatal(1,"config Flash watchdog state=%0d store=%0d code=%h",dut.state,dut.store_proc.state,error_code);end
endmodule
